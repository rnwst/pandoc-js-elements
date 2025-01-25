-- Utilities -------------------------------------------------------------------
local function has_value(tab, val)
    for _, v in pairs(tab) do
        if v == val then
            return true
        end
    end
    return false
end


-- Remove value from numerically indexed table.
local function remove_value(tab, val)
    for i, v in ipairs(tab) do
        if v == val then
            table.remove(tab, i)
            return
        end
    end
end


local function isempty(tab)
    return next(tab) == nil
end


local function write_file(path, content)
    local dir = pandoc.path.directory(path)
    -- Attempt to create directory, don't throw error if it already exists.
    pcall(pandoc.system.make_directory, dir, true)
    local file = io.open(path, 'w')
    file:write(content)
    file:close()
end


-- Plain text is not considered since we need a placeholder element in order to
-- replace is later.
local phrasing_tags = {
    'abbr', 'audio', 'b', 'bdi', 'bdo', 'br', 'button', 'canvas', 'cite',
    'code', 'data', 'datalist', 'dfn', 'em', 'embed', 'i', 'iframe', 'img',
    'input', 'kbd', 'label', 'mark', 'math', 'meter', 'noscript', 'object',
    'picture', 'progress', 'q', 'ruby', 's', 'samp', 'script', 'select', 'slot',
    'small', 'span', 'strong', 'sub', 'sup', 'svg', 'template', 'textarea',
    'time', 'u', 'var', 'video', 'wbr'
}


-- Flow tags 'main' and 'h1' were left out, as they should not be used.
local flow_tags_less_phrasing_tags = {
    'a', 'address', 'article', 'aside', 'blockquote', 'del', 'details',
    'dialog', 'div', 'dl', 'fieldset', 'figure', 'footer', 'form', 'h2', 'h3',
    'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'ins', 'map', 'mark', 'math',
    'menu', 'meter', 'nav', 'noscript', 'object', 'ol', 'output', 'p',
    'picture', 'pre', 'search', 'section', 'table', 'ul'
}


local function is_custom_tag(tag)
    -- After the first character, HTML custom elements can contain non-ASCII
    -- characters, as documented here:
    -- https://html.spec.whatwg.org/multipage/custom-elements.html#prod-pcenchar
    -- However, since Lua's string library only deals with ASCII, this is not
    -- implemented.
    local disallowed_names = {
        'annotation-xml', 'color-profile', 'font-face', 'font-face-src',
        'font-face-uri', 'font-face-format', 'font-face-name', 'missing-glyph'
    }
    return tag:match('^[a-z][a-z%-%.0-9_]+$') and tag:match('^[^%-]*%-[^%-]*$')
        and not has_value(disallowed_names, tag)
end


local function url_decode(s)
    return string.gsub(s, '%%(%x%x)', function(hex)
        return string.char(tonumber(hex, 16))
    end)
end
--------------------------------------------------------------------------------


local js_elements = false
local contains_js_elements = false
local code_block_counter = 0
local placeholder_elt_counter = 0
local md_label_counter = 0
local md_labels = {}

local elements_js = {[[
// Header ----------------------------------------------------------------------

'use strict';

const replacePlaceholder = async (placeholderId, replacement) => {
  const placeholder = document.getElementById(placeholderId);
  if (placeholder.id.match(/^placeholder-elt-\d+$/)) {
    placeholder.removeAttribute('id');
  }
  // Await replacement in case it is a promise.
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
]]}


local function create_md_labels(elt)
    -- Attributes whose keys start with `md.` are parsed as markdown and
    -- the resultant HTML elements appended to the document. They can later
    -- be retrieved via JS and incoporated into generated elements. This is
    -- useful e.g. when using mathematical symbols in figure axis labels.
    local label_defs = {}
    for key, val in pairs(elt.attributes) do
        -- If key starts with 'md.' and has at least one character
        -- afterwards...
        if key:find('^md%.[0-9a-zA-Z_]+$') then
            -- TBD: use run_lua_filter function to run appropriate filters,
            -- such as pandoc-xref-native (once it's been written...)
            local inlines =
                pandoc.read(val, 'markdown', PANDOC_READER_OPTIONS)
                    .blocks[1].content
            elt.attributes[key] = nil -- remove attribute
            md_label_counter = md_label_counter + 1
            local label_id = 'md-label-' .. md_label_counter
            local span = pandoc.Span(inlines,
                                     pandoc.Attr(label_id, {'md-label'}))
            table.insert(md_labels, pandoc.Plain(span))
            table.insert(label_defs, string.format(
                "%s = document.getElementById('%s');", key, label_id))
        end
    end
    local label_defs_js = ''
    if not isempty(label_defs) then
        label_defs_js = string.format([[
// Auto-generated markdown label definitions
%s

]], table.concat(label_defs, '\n'))
    end

    return label_defs_js
end


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


local function insert_elt_js(label_defs_js, placeholder_id, inline_js)
    table.insert(elements_js, string.format([[

/* *****************************************************************************
 * Element #%s */
%s
replacePlaceholder('%s', %s);
]], placeholder_elt_counter, label_defs_js, placeholder_id, inline_js))
end


local function code_block(elt)
    if has_value(elt.classes, 'js') and elt.attributes.exec ~= false then
        contains_js_elements = true

        code_block_counter = code_block_counter + 1
        table.insert(elements_js, string.format([[

/* *****************************************************************************
 * Code block #%s */
]], code_block_counter))

        local label_defs_js = create_md_labels(elt)
        if label_defs_js ~= '' then
            table.insert(elements_js, label_defs_js)
        end
        table.insert(elements_js, elt.text.. '\n')

        if has_value(elt.classes, 'include') then
            remove_value(elt.classes, 'include')
            return elt
        end

        return {}
    end
end


local function process_inline_code(elt, is_inline)
    if has_value(elt.classes, 'js') and elt.attributes.exec ~= false then
        contains_js_elements = true
        remove_value(elt.classes, 'js')

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
            if has_value(phrasing_tags, given_tag)
              or (not is_inline
                  and has_value(flow_tags_less_phrasing_tags, given_tag))
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


local function code(elt)
    return process_inline_code(elt, true)
end


local function para(elt)
    if #elt.content == 1 and elt.content[1].tag == 'Code' then
        return process_inline_code(elt.content[1], false)
    end
end


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


local function get_js_path(doc_rel_path)
    local md_dir = pandoc.path.directory(PANDOC_STATE.input_files[1])
    return pandoc.path.join({md_dir, doc_rel_path})
end


if FORMAT:match 'html' or FORMAT:match 'native' or FORMAT:match 'json' then
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
                    local attr = pandoc.Attr('md-labels', {},
                                             {style = 'display: none'})
                    table.insert(doc.blocks,
                                 pandoc.Div(pandoc.Blocks(md_labels), attr))

                    -- Write elements.js.
                    local rel_path = 'js/elements.js';
                    write_file(
                        get_js_path(rel_path),
                        table.concat(elements_js, '\n')
                    )

                    -- Add to header-includes for standalone documents.
                    local scriptElt = pandoc.RawInline(
                        'html',
                        '<script type="module" src="' .. rel_path ..
                            '"></script>'
                    )
                    if doc.meta['header-includes'] then
                        table.insert(doc.meta['header-includes'], scriptElt)
                    else
                        doc.meta['header-includes'] = {scriptElt}
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
