'use strict';

/**
 * Utilities for creating responsive elements.
 */


/**
 * Return width of provided element in 'px'.
 * @param {Element} elt - Element
 * @return {number}
 */
export function width(elt) {
  return elt.getBoundingClientRect().width;
}


/**
 * Return height of provided element in 'px'.
 * @param {Element} elt - Element
 * @return {number}
 */
export function height(elt) {
  return elt.getBoundingClientRect().height;
}


/**
 * Return font size of provided element in 'px'.
 * @param {Element} elt - Element
 * @return {number}
 */
export function fontSize(elt) {
  return parseFloat(getComputedStyle(elt).getPropertyValue('font-size'));
}


/**
 * Return width of provided element in 'em'.
 * @param {Element} elt - Element
 * @return {number}
 */
export function emWidth(elt) {
  return width(elt)/fontSize(elt);
}


/**
 * Return height of provided element in 'em'.
 * @param {Element} elt - Element
 * @return {number}
 */
export function emHeight(elt) {
  return height(elt)/fontSize(elt);
}


/**
 * Clone element attributes from one element to another.
 * @param {Element} oldElt - Element from which to clone attributes
 * @param {Element} newElt - Element to which to clone attributes
 */
export function cloneAttrs(oldElt, newElt) {
  [...oldElt.attributes].forEach(({name, value}) =>
    newElt.setAttribute(name, value),
  );
}


/**
 * Return function which takes an element as its only argument. The provided
 * argument is expected to be a function, which, when passed an element, returns
 * a new element, which is to replace the passed element.
 * @param {function(Element): Element} createElt - Function which creates new element from old
 * @return {function(Element): Element} - Replaces given element when executed.
 */
export function responsiveElt(createElt) {
  if ((typeof createElt) != 'function') {
    throw new Error('Provided argument is not a function!');
  }
  const replaceElt = async (eltToBeReplaced) => {
    if (!(eltToBeReplaced instanceof Element)) {
      throw new Error('Provided element is not an Element!');
    }
    if (!(document.contains(eltToBeReplaced))) {
      throw new Error('Provided element is not contained in document!');
    }
    const newElt = createElt(eltToBeReplaced);
    if (!(newElt instanceof Element)) {
      throw new Error('Return value of provided function is not an Element!');
    }
    console.debug('Replacing element', eltToBeReplaced, 'with', newElt);
    eltToBeReplaced.replaceWith(newElt);
    // If the element is an image, we need to wait for it to be loaded before
    // taking dimensions.
    if (newElt instanceof HTMLImageElement) {
      await new Promise((resolve) => {
        newElt.onload = resolve;
        newElt.onerror = resolve;
      });
    }
    const oldWidth = width(newElt);
    const oldHeight = height(newElt);
    new ResizeObserver((_entries, observer) => {
      if ((oldWidth != width(newElt)) ||
          (oldHeight != height(newElt))) {
        observer.disconnect();
        replaceElt(newElt);
      }
    }).observe(newElt);
  };

  return replaceElt;
}
