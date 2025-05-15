-- <Utilities> ---------------------------------------------------------------------------------------------------------

---Write content to given file path.
---@param path string
---@param content string
local function write_file(path, content)
    local dir = pandoc.path.directory(path)
    -- Attempt to create directory, don't throw error if it already exists.
    pcall(pandoc.system.make_directory, dir, true)
    local file = io.open(path, 'w')
    if file then
        file:write(content)
        file:close()
    end
end


-- Plain text is not considered since we need a placeholder element in order to
-- replace it later.
---@type List<string>
local phrasing_tags = pandoc.List{
    'abbr', 'audio', 'b', 'bdi', 'bdo', 'br', 'button', 'canvas', 'cite',
    'code', 'data', 'datalist', 'dfn', 'em', 'embed', 'i', 'iframe', 'img',
    'input', 'kbd', 'label', 'mark', 'math', 'meter', 'noscript', 'object',
    'picture', 'progress', 'q', 'ruby', 's', 'samp', 'script', 'select', 'slot',
    'small', 'span', 'strong', 'sub', 'sup', 'svg', 'template', 'textarea',
    'time', 'u', 'var', 'video', 'wbr'
}


-- Flow tags 'main' and 'h1' were left out, as they should not be used.
---@type List<string>
local flow_tags_less_phrasing_tags = pandoc.List{
    'a', 'address', 'article', 'aside', 'blockquote', 'del', 'details',
    'dialog', 'div', 'dl', 'fieldset', 'figure', 'footer', 'form', 'h2', 'h3',
    'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'ins', 'map', 'mark', 'math',
    'menu', 'meter', 'nav', 'noscript', 'object', 'ol', 'output', 'p',
    'picture', 'pre', 'search', 'section', 'table', 'ul'
}


---Determine whether the given HTML tag is a custom tag.
---@param tag string
---@return boolean
local function is_custom_tag(tag)
    -- After the first character, HTML custom elements can contain non-ASCII
    -- characters, as documented here:
    -- https://html.spec.whatwg.org/multipage/custom-elements.html#prod-pcenchar
    -- However, since Lua's string library only deals with ASCII, this is not
    -- currently implemented.
    local disallowed_names = pandoc.List{
        'annotation-xml', 'color-profile', 'font-face', 'font-face-src',
        'font-face-uri', 'font-face-format', 'font-face-name', 'missing-glyph'
    }
    return tag:match('^[a-z][a-z%-%.0-9_]+$') and tag:match('^[^%-]*%-[^%-]*$')
        and not disallowed_names:includes(tag)
end


---Decode a URL-encoded string.
---@param s any
---@return string
local function url_decode(s)
    local decoded = string.gsub(s, '%%(%x%x)', function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

-- </Utilities> --------------------------------------------------------------------------------------------------------


---@type boolean  Whether to execute this filter; overwritten by document front matter
local js_elements = false

---@type boolean  Whether document contains executable JS code
local contains_js_elements = false

---@type integer  Counter for code blocks
local code_block_counter = 0

---@type integer  Counter for placeholder elements
local placeholder_elt_counter = 0

---@type integer  Counter for markdown labels
local md_label_counter = 0

---@type List<Plain>
local md_labels = pandoc.List{}

---@type List<string>
local elements_js = pandoc.List{[[
// Header ----------------------------------------------------------------------

'use strict';

const replacePlaceholder = async (placeholderId, replacement) => {
  const placeholder = document.getElementById(placeholderId);
  if (placeholder.id.match(/^placeholder-elt-\d+$/)) {
    placeholder.removeAttribute('id');
  }
  // Await replacement in case it is a Promise.
  replacement = await replacement;
  const replacementType = typeof replacement;
  if (replacementType === 'object' && replacement instanceof Element) {
    placeholder.replaceWith(replacement);
  } else if (replacementType === 'string' || replacementType === 'number') {
    placeholder.replaceWith(String(replacement));
  } else if (replacementType === 'function') {
    try {
      await replacement(placeholder);
    } catch (error) {
      console.error(
          'An error occurred while executing the replacement function for ' +
          'placeholder element', placeholder, ':', error,
      );
    }
  } else {
    console.error(
        'Cannot replace placeholder element',
        placeholder,
        'with',
        replacement,
        'because it is neither an instance of "Element" nor a string nor a ' +
        'number nor a function nor a Promise which resolves to any of the ' +
        'above.',
    );
  }
};

const md = {};

const getMDLabel = (id) => {
    const elt = document.getElementById(id);
    elt.removeAttribute('id');
    return elt;
};
]]}


---Create JS which retrieves Markdown label elements.
---@param elt (CodeBlock | Code | Image)
---@return string
local function create_md_labels(elt)
    -- Attributes whose keys start with `md.` are parsed as markdown and
    -- the resultant HTML elements appended to the document. They can later
    -- be retrieved via JS and incoporated into generated elements. This is
    -- useful e.g. when using mathematical symbols in figure axis labels.
    ---@type List<string>
    local label_defs = pandoc.List{}
    for key, val in pairs(elt.attributes) do
        -- If key starts with 'md.' and has at least one character
        -- afterwards...
        if key:find('^md%.[0-9a-zA-Z_]+$') then
            -- TBD: use run_lua_filter function to run appropriate filters,
            -- such as pandoc-xref-native (once it's been written...)
            local inlines = pandoc.read(val, 'markdown', PANDOC_READER_OPTIONS).blocks[1].content
            elt.attributes[key] = nil -- remove attribute
            md_label_counter = md_label_counter + 1
            local label_id = 'md-label-' .. md_label_counter
            local span = pandoc.Span(inlines, pandoc.Attr(label_id))
            md_labels:insert(pandoc.Plain(span))
            label_defs:insert(string.format("%s = getMDLabel('%s');", key, label_id))
        end
    end
    local label_defs_js = ''
    if #label_defs ~= 0 then
        label_defs_js = string.format([[
// Auto-generated Markdown label definitions
%s

]], table.concat(label_defs, '\n'))
    end

    return label_defs_js
end


---Return Id for placeholder elements.
---@param elt (CodeBlock | Code | Image)
---@return string
local function get_placeholder_id(elt)
    local id
    if elt.identifier ~= '' and elt.identifier ~= nil then
        id = elt.identifier
    else
        placeholder_elt_counter = placeholder_elt_counter + 1
        id = 'placeholder-elt-' .. placeholder_elt_counter
    end
    return id
end


---Add JS to replace placeholder element to module.
---@param label_defs_js string
---@param placeholder_id string
---@param inline_js string
local function insert_elt_js(label_defs_js, placeholder_id, inline_js)
    elements_js:insert(string.format([[

/* *****************************************************************************
 * Element #%s */
%s
replacePlaceholder('%s', %s);
]], placeholder_elt_counter, label_defs_js, placeholder_id, inline_js))
end


---Add code block JS to module.
---@param elt CodeBlock
---@return CodeBlock | {} | nil
local function code_block(elt)
    if elt.classes:includes('js') and elt.attributes.exec ~= 'false' then
        contains_js_elements = true

        code_block_counter = code_block_counter + 1
        elements_js:insert(string.format([[

/* *****************************************************************************
 * Code block #%s */
]], code_block_counter))

        local label_defs_js = create_md_labels(elt)
        if label_defs_js ~= '' then
            elements_js:insert(label_defs_js)
        end
        elements_js:insert(elt.text .. '\n')

        if elt.attributes.include == 'true' then
            elt.classes:remove(table.pack(elt.classes:find('include'))[2])
            return elt
        end

        return {} -- delete element from AST
    elseif elt.classes:includes('js') and elt.attributes.exec == 'false'
      and elt.attributes.include == 'false' then
        return {} -- delete element from AST
    end
end


---Process inline code elements.
---@param elt       Code     Code element
---@param is_inline boolean  whether to use <div> or <span> for placeholder element
---@return RawInline | RawBlock | nil
local function process_inline_code(elt, is_inline)
    if elt.classes:includes('js') and elt.attributes.exec ~= false then
        contains_js_elements = true
        elt.classes:remove(table.pack(elt.classes:find('js'))[2])

        elt.identifier = get_placeholder_id(elt)

        insert_elt_js(create_md_labels(elt), elt.identifier, elt.text)

        local placeholder_tag
        if is_inline then
            placeholder_tag = 'span'
        else
            placeholder_tag = 'div'
        end

        if elt.attributes.tag then
            local given_tag = elt.attributes.tag
            if phrasing_tags:includes(given_tag)
              or (not is_inline and flow_tags_less_phrasing_tags:includes(given_tag))
              or is_custom_tag(given_tag) then
                placeholder_tag = given_tag
                elt.attributes.tag = nil
            end
        end

        local div_html =
            pandoc.write(pandoc.Pandoc({pandoc.Div({}, elt.attr)}), 'html')
        local placeholder_html =
            div_html:gsub('^<div(.*)>%s*</div>%s*$',
                          string.format('<%s%%1></%s>',
                                        placeholder_tag,
                                        placeholder_tag))

        if is_inline then
            return pandoc.RawInline('html', placeholder_html)
        end
        return pandoc.RawBlock('html', placeholder_html)
    end
end


---Filter function for [Code](lua://Code) elements.
---@param elt Code
---@return RawInline | nil
local function code(elt)
    ---@type RawInline | nil
    return process_inline_code(elt, true)
end


---Filter function for [Para](lua://Para) elements.
---@param elt Para
---@return RawBlock | nil
local function para(elt)
    if #elt.content == 1 and elt.content[1].tag == 'Code' then
        local code_elt = elt.content[1]
        ---@cast code_elt Code
        ---@type RawBlock | nil
        return process_inline_code(code_elt, false)
    end
end


---Filter function for [Image](lua://Image) elements.
---@param elt Image
---@return Image | nil
local function image(elt)
    if contains_js_elements then
        local js = url_decode(elt.src):match('^`(.+)`$')
        if js then
            elt.identifier = get_placeholder_id(elt)
            elt.src = ''
            insert_elt_js(create_md_labels(elt), elt.identifier, js)
            return elt
        end
    end
end


if FORMAT:match 'html' or FORMAT:match 'native' or FORMAT:match 'json' then
    ---@type Filter
    return {
        {
            Meta = function(meta)
                if meta['js-elements'] == true then
                    js_elements = true;
                end
            end
        },
        {
            Pandoc = function(doc)
                if js_elements then
                    return doc:walk({
                        traverse = 'topdown',
                        CodeBlock = code_block,
                        Code = code,
                        Para = para,
                        Image = image
                    })
                end
            end
        },
        {
            Pandoc = function(doc)
                if contains_js_elements then
                    -- Append md_labels to document.
                    local attr = pandoc.Attr('md-labels', {}, {style = 'display: none'})
                    doc.blocks:insert(pandoc.Div(pandoc.Blocks(md_labels), attr))

                    -- Write elements.js.
                    local rel_path = 'js/elements.js';
                    write_file(
                        pandoc.path.join({pandoc.path.directory(PANDOC_STATE.input_files[1]), rel_path}),
                        table.concat(elements_js, '\n')
                    )

                    -- Add to header-includes for standalone documents.
                    local script_elt = pandoc.RawInline(
                        'html',
                        '<script type="module" src="' .. rel_path ..
                            '"></script>'
                    )
                    if doc.meta['header-includes'] then
                        (doc.meta['header-includes'] --[[@as List<string>]]):insert(script_elt)
                    else
                        doc.meta['header-includes'] = pandoc.List{script_elt}
                    end
                    -- Also define 'elementsJS' metadata key to allow more
                    -- fine-grained control over module loading.
                    doc.meta['js-elements-path'] = rel_path

                    return pandoc.Pandoc(doc.blocks, doc.meta)
                end
            end
        }
    }
end
