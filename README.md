# pandoc-js-elements

`pandoc-js-elements` is a [pandoc](https://pandoc.org/) [Lua filter](https://pandoc.org/lua-filters.html) which enables the execution of JavaScript code blocks as well as the insertion of elements created with JS into the document. This permits inclusion of dynamically generated content such as interactive and responsive figures or dynamic textual elements in HTML output.


## Usage

### Executable code blocks

To execute JavaScript code blocks, the frontmatter key `js-elements` needs to be set
to `true`:
```md
---
author: R. N. West
title: Dynamic Documents with JavaScript!
js-elements: true
---

Document content...
```
Code blocks with class `js` will then be executed instead of being included in the document:
````md
```js
console.log('The date and time is ' + new Date());
```
````
To prevent execution of a JavaScript code block, set the `exec` attribute to `false`:
````md
```{.js exec=false}
// This code is not executed!
console.log('The date and time is ' + new Date());
```
````
The code block is then included in the document as it would normally be. To prevent execution *and* exclude the code block from the document, set the `include` attribute to `false`:
````md
```{.js exec=false include=false}
// This code is neither executed nor included in the document.
console.log('The date and time is ' + new Date());
```
````
To execute a code block *and* include it in the document, set the `include` attribute to `true`:
````md
```{.js include=true}
// This code is executed and included in the document.
console.log('The date and time is ' + new Date());
```
````
`pandoc-js-elements` places all executable code blocks in a single JavaScript module, which is written to the path `js/elements.js` and added to the `header-includes` template variable (alternatively, this file location is also available under the document metadata variable `js-elements-path`). Therefore, `import` statements may be used:
````md
```js
import * as d3 from "https://cdn.jsdelivr.net/npm/d3@7/+esm";
```
````


### Inserting elements into the document

Elements that were previously created with JS can be included in the document by referencing them in an inline JS code element:
````md
```js
const span = document.createElement('span');
span.textContent = 'I am a `<span>`.'
```
This is a span: `span`{.js}
````
which results in the following HTML fragment:
> ```html
> <p>This is a span: <span>I am a &lt;span&gt;.</span></p>
> ```
The expression in the inline code element needs to either be an object with [`Element`](https://developer.mozilla.org/en-US/docs/Web/API/Element) in its prototype chain or a string, number, or function (or a [`Promise`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise) which resolves to any of these). Here is an example of a number:
```md
The number Pi is `Math.PI`{.js}.
```
which results in the following HTML fragment:
> ```html
> <p>The number Pi is 3.141592653589793.</p>
> ```
If the provided expression is a function, a placeholder element will be created in place of the inline code element (with the specified Id, classes, and attributes), and the function will be executed once after the document has loaded with the placeholder element passed as the only argument.

### Markdown attributes

Sometimes it can be helpful to have access to markdown snippets from within JavaScript, e.g. to include markdown-based axes labels in a graph. Since in the browser we do not have access to pandoc anymore, these labels need to be precompiled to HTML. `pandoc-js-elements` offers a convenient mechanism for this. Attributes of executable code blocks which start with `md.` are automatically compiled to HTML using pandoc and are available from within JavaScript under the same name (the object `md`):
````md
```{.js md.xlabel='$x$' md.ylabel='$\\dfrac{dx}{dy}$'}
console.log(md.xlabel.outerHTML);
console.log(md.ylabel.outerHTML);
```
````
which prints the following output to the devtools console (depending on which
[`html-math-method`](https://pandoc.org/MANUAL.html#math-rendering-in-html-1)
was selected - `katex` in this case):
> ```html
> <span><span class="math inline">x</span></span>
> ```
> ```html
> <span><span class="math inline">\dfrac{dx}{dy}</span></span>
> ```
(Note the requirement to escape backslashes in code block attributes.)

<!--
# Installation

# Internals
-->


## Other output formats

Currently, HTML is the only supported output format. In the future, other formats such as LaTeX could be supported as well (e.g. to allow the publication of an interactive HTML document as a non-interactive academic paper in a journal), though dynamic features would obviously only work in HTML.


## License

© 2025 R. N. West. Released under the [GPL](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) version 2 or greater. This software carries no warranty of any kind.
