-- <Utilities> ---------------------------------------------------------------------------------------------------------

---Read file contents.
---@param path string
---@return string | nil
local function read_file(path)
   local file = io.open(path, 'r') -- "r" means read mode
   if not file then
      pandoc.log.warn('js-elements: Could not open file ' .. path)
      return nil
   end
   local content = file:read('*a') -- "*a" reads the whole file
   file:close()
   return content
end

---Write given content to given file path.
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
local phrasing_tags = pandoc.List {
   'abbr',
   'audio',
   'b',
   'bdi',
   'bdo',
   'br',
   'button',
   'canvas',
   'cite',
   'code',
   'data',
   'datalist',
   'dfn',
   'em',
   'embed',
   'i',
   'iframe',
   'img',
   'input',
   'kbd',
   'label',
   'mark',
   'math',
   'meter',
   'noscript',
   'object',
   'picture',
   'progress',
   'q',
   'ruby',
   's',
   'samp',
   'script',
   'select',
   'slot',
   'small',
   'span',
   'strong',
   'sub',
   'sup',
   'svg',
   'template',
   'textarea',
   'time',
   'u',
   'var',
   'video',
   'wbr',
}

-- Flow tags 'main' and 'h1' were left out, as they should not be used.
---@type List<string>
local flow_tags_less_phrasing_tags = pandoc.List {
   'a',
   'address',
   'article',
   'aside',
   'blockquote',
   'del',
   'details',
   'dialog',
   'div',
   'dl',
   'fieldset',
   'figure',
   'footer',
   'form',
   'h2',
   'h3',
   'h4',
   'h5',
   'h6',
   'header',
   'hgroup',
   'hr',
   'ins',
   'map',
   'mark',
   'math',
   'menu',
   'meter',
   'nav',
   'noscript',
   'object',
   'ol',
   'output',
   'p',
   'picture',
   'pre',
   'search',
   'section',
   'table',
   'ul',
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
   local disallowed_names = pandoc.List {
      'annotation-xml',
      'color-profile',
      'font-face',
      'font-face-src',
      'font-face-uri',
      'font-face-format',
      'font-face-name',
      'missing-glyph',
   }
   return tag:match('^[a-z][a-z%-%.0-9_]+$') and tag:match('^[^%-]*%-[^%-]*$') and not disallowed_names:includes(tag)
end

---Decode a URL-encoded string.
---@param s any
---@return string
local function url_decode(s)
   local decoded = string.gsub(s, '%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end)
   return decoded
end

---@type string  Base64 characters used for Base64 encoding
local BASE64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

---Encode a series of numbers into a VLQ Base64 string.
---@param nums integer[]
---@return string
local function nums2VLQs(nums)
   ---@type string[]
   local vlqs = {}
   for _, num in ipairs(nums) do
      -- Convert number to VLQ format
      local vlq = num < 0 and (-num << 1) + 1 or (num << 1)

      local result = ''
      repeat
         local chunk = vlq & 31 -- Get the last 5 bits
         vlq = vlq >> 5 -- Shift right by 5 bits
         if vlq > 0 then
            chunk = chunk | 32 -- Set the continuation bit if there are more groups
         end
         result = result .. BASE64_CHARS:sub(chunk + 1, chunk + 1)
      until vlq == 0

      table.insert(vlqs, result)
   end
   return table.concat(vlqs)
end

---Encode the given string in Base64.
---@param str string
local function base64_encode(str)
   ---@type string[]
   local base64 = {}

   local pad_length = (3 - (#str % 3)) % 3
   local padded_str = str .. string.char(0):rep(pad_length) -- pad with zeroes

   ---@type fun(idx: integer): number
   local function byte_at(idx) return padded_str:sub(idx, idx):byte() end

   ---@type fun(num: integer)
   local function insert_char(num) table.insert(base64, BASE64_CHARS:sub(num + 1, num + 1)) end

   for i = 1, #padded_str, 3 do
      local first, second, third = byte_at(i), byte_at(i + 1), byte_at(i + 2)
      insert_char(first >> 2)
      insert_char(((first & 3) << 4) + (second >> 4)) -- the two bit shifts...
      insert_char(((second & 15) << 2) + (third >> 6)) -- ...need to sum to 8
      insert_char(third & 63)
   end
   -- Now we have to deal with padding.
   if pad_length > 0 then base64[#base64] = '=' end
   if pad_length > 1 then base64[#base64 - 1] = '=' end
   return table.concat(base64)
end

---Split a given string into lines.
---@param str string
---@return List<string>
local function split_lines(str)
   local lines = pandoc.List {}
   local pos = 1

   while true do
      local start, finish = str:find('\r?\n', pos)
      if not start then
         -- Add the remaining text (could be empty).
         lines:insert(string.sub(str, pos))
         break
      end
      lines:insert(string.sub(str, pos, start - 1))
      pos = finish + 1
   end

   return lines
end

---Escape a string according to the JSON specification so it can be used in a
---JSON file.
---@param str string
---@return string
local function json_escape(str)
   local entities = {
      ['"'] = '\\"',
      ['\\'] = '\\\\',
      ['\b'] = '\\b',
      ['\f'] = '\\f',
      ['\n'] = '\\n',
      ['\r'] = '\\r',
      ['\t'] = '\\t',
   }
   local escaped_str = str:gsub('["\\\b\f\n\r\t]', entities)
   return escaped_str
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
local md_labels = pandoc.List {}

-- Each JavaScript line becomes a separate item in this List.
-- The `mappings` entry is a List of a List of integers, where the
-- integer list each contains a source mapping with two fields:
-- Output column and input string index.
---@type List<{content: string, mappings: List<List<integer>>}>
local elements_js = pandoc.List {}

-- luacheck: ignore 631
---@type string  Markdown source file content needed for source mapping, to be populated once we know the document contains JS elements
local source = ''

---@type integer  Last Markdown source file position (row and column), used for source mapping purposes
local source_pos = 0

---Add a generated JavaScript code block to the module.
---A code block is a bunch of code that includes newlines.
---Generated code is code that has no equivalent in the Markdown file and therefore isn't mapped.
---@param js              string   JS code
---@param start_new_line? boolean  whether to start a new line, defaults to `true`
local function add_generated_js_block(js, start_new_line)
   local lines = split_lines(js)
   local loop_start_idx = 1
   if start_new_line == false then
      local last_entry = elements_js[#elements_js]
      last_entry.content = last_entry.content .. lines[1]
      loop_start_idx = 2
   end
   for i = loop_start_idx, #lines do
      elements_js:insert { content = lines[i], mappings = pandoc.List {} }
   end
end

---Add JavaScript code from the source to the module and update source map.
---@param js              string   JS code
---@param source_str_idx? integer  source string index of code for mapping
---@param start_new_line? boolean  whether to start a new line, defaults to `true`
local function add_mapped_line(js, source_str_idx, start_new_line)
   local lines = split_lines(js)
   if #lines > 1 then error('String passed to `add_mapped_line` contains at least one newline char!', 2) end
   if start_new_line == false then
      local last_entry = elements_js[#elements_js]
      -- Source map text columns start at zero.
      last_entry.mappings:insert(pandoc.List { #last_entry.content, source_str_idx })
      last_entry.content = last_entry.content .. lines[1]
   else
      elements_js:insert {
         content = lines[1],
         mappings = pandoc.List { pandoc.List { 0, source_str_idx } },
      }
   end
end

add_generated_js_block([[
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

]])

---Create JS which retrieves Markdown label elements.
---@param elt (CodeBlock | Code | Image)
---@return string
local function create_md_labels(elt)
   -- Attributes whose keys start with `md.` are parsed as markdown and
   -- the resultant HTML elements appended to the document. They can later
   -- be retrieved via JS and incoporated into generated elements. This is
   -- useful e.g. when using mathematical symbols in figure axis labels.
   ---@type List<string>
   local label_defs = pandoc.List {}
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
      label_defs_js = string.format(
         [[
// Auto-generated Markdown label definitions
%s

]],
         table.concat(label_defs, '\n')
      )
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
   add_generated_js_block(string.format(
      [[
/* *****************************************************************************
 * Element #%s */
%s
replacePlaceholder('%s', ]],
      placeholder_elt_counter,
      label_defs_js,
      placeholder_id
   ))
   local start, finish = source:find('`' .. inline_js .. '`', source_pos, true)
   source_pos = finish or source_pos
   if start then
      add_mapped_line(inline_js, start + 1, false)
   else
      add_generated_js_block(inline_js, false)
   end
   add_generated_js_block(');\n\n', false)
end

---Add code block JS to module.
---@param elt CodeBlock
---@return CodeBlock | {} | nil
local function code_block(elt)
   if elt.classes:includes('js') and elt.attributes.exec ~= 'false' then
      contains_js_elements = true

      code_block_counter = code_block_counter + 1
      add_generated_js_block(string.format(
         [[
/* *****************************************************************************
 * Code block #%s */
]],
         code_block_counter
      ))

      local label_defs_js = create_md_labels(elt)
      if label_defs_js ~= '' then add_generated_js_block(label_defs_js) end

      -- This is a very crude method to find the corresponding source position,
      -- but it should work most of the time. Note that this method doesn't work
      -- for indented code blocks.
      -- If no source position is found, add the code block unmapped.
      local start, finish = source:find(elt.text, source_pos, true)
      if start then
         source_pos = finish + 1
         local lines = split_lines(elt.text)
         add_mapped_line(lines[1], start)
         for _, line in ipairs { table.unpack(lines, 2) } do
            start = source:find('\r?\n', start + 1)
            add_mapped_line(line, start + 1)
         end
      else
         add_generated_js_block(elt.text)
      end
      add_generated_js_block('\n')

      if elt.attributes.include == 'true' then
         elt.classes:remove(table.pack(elt.classes:find('include'))[2])
         return elt
      end

      return {} -- delete element from AST
   elseif elt.classes:includes('js') and elt.attributes.exec == 'false' and elt.attributes.include == 'false' then
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
         if
            phrasing_tags:includes(given_tag)
            or (not is_inline and flow_tags_less_phrasing_tags:includes(given_tag))
            or is_custom_tag(given_tag)
         then
            placeholder_tag = given_tag
            elt.attributes.tag = nil
         end
      end

      local div_html = pandoc.write(pandoc.Pandoc { pandoc.Div({}, elt.attr) }, 'html')
      local placeholder_html =
         div_html:gsub('^<div(.*)>%s*</div>%s*$', string.format('<%s%%1></%s>', placeholder_tag, placeholder_tag))

      if is_inline then return pandoc.RawInline('html', placeholder_html) end
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

---Construct source map.
---@return string
local function build_source_map()
   local mappings_lines = pandoc.List {}
   local prev_source_line = 0
   local prev_source_column = 0
   for _, entry in ipairs(elements_js) do
      local vlqs = pandoc.List {}
      local prev_output_column = 0
      for _, mapping in ipairs(entry.mappings) do
         local output_column = mapping[1]
         local input_idx = mapping[2]
         local source_line = ({ source:sub(1, input_idx - 1):gsub('\n', '') })[2]
         local source_column = #(
            ({ source:sub(1, input_idx - 1):find('\n([^\n]-)$') })[3] or source:sub(1, input_idx - 1)
         )
         -- Output column, source index, source line, source column
         -- Output column, source line, and source column are relative to
         -- their previous occurrences. Output column resets on each new line.
         -- See https://tc39.es/ecma426/#sec-mappings
         vlqs:insert(nums2VLQs {
            output_column - prev_output_column,
            0,
            source_line - prev_source_line,
            source_column - prev_source_column,
         })
         prev_output_column = output_column
         prev_source_line = source_line
         prev_source_column = source_column
      end
      mappings_lines:insert(table.concat(vlqs, ','))
   end
   local mappings = table.concat(mappings_lines, ';')
   return ([[
{
  "version" : 3,
  "file": "elements.js",
  "sources": ["%s"],
  "sourcesContent": ["%s"],
  "mappings": "%s"
}
]]):format(pandoc.path.filename(PANDOC_STATE.input_files[1]), json_escape(source), mappings)
end

---Build the content of the file `js/elements.js`.
---@return string
local function build_elements_js()
   local js = table.concat(elements_js:map(function(entry) return entry.content end), '\n')
   return js .. '\n//# sourceMappingURL=data:application/json;base64,' .. base64_encode(build_source_map())
end

if
   pandoc
      .List({
         'chunkedhtml',
         'html',
         'html5',
         'html4',
         'slideous',
         'slidy',
         'dzslides',
         'revealjs',
         's5',
      })
      :includes(FORMAT) or FORMAT:match('native')
then
   ---@type Filter
   return {
      {
         Meta = function(meta)
            if meta['js-elements'] == true then
               js_elements = true
               source = read_file(PANDOC_STATE.input_files[1]) or ''
            end
         end,
      },
      {
         Pandoc = function(doc)
            if js_elements then
               return doc:walk {
                  traverse = 'topdown',
                  CodeBlock = code_block,
                  Code = code,
                  Para = para,
                  Image = image,
               }
            end
         end,
      },
      {
         Pandoc = function(doc)
            if contains_js_elements then
               -- Append md_labels to document.
               local attr = pandoc.Attr('md-labels', {}, { style = 'display: none' })
               doc.blocks:insert(pandoc.Div(pandoc.Blocks(md_labels), attr))

               -- Write elements.js.
               local rel_path = 'js/elements.js'
               write_file(
                  pandoc.path.join { pandoc.path.directory(PANDOC_STATE.input_files[1]), rel_path },
                  build_elements_js()
               )

               -- Add to header-includes for standalone documents.
               local script_elt = pandoc.RawInline('html', '<script type="module" src="' .. rel_path .. '"></script>')
               if doc.meta['header-includes'] then
                  (doc.meta['header-includes'] --[[@as List<string>]]):insert(script_elt)
               else
                  doc.meta['header-includes'] = pandoc.List { script_elt }
               end
               -- Also define 'elementsJS' metadata key to allow more
               -- fine-grained control over module loading.
               doc.meta['js-elements-path'] = rel_path

               return pandoc.Pandoc(doc.blocks, doc.meta)
            end
         end,
      },
   }
end
