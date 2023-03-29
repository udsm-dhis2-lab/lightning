import metadata_dhis2 from './dhis2.js';
import metadata_salesforce from './salesforce.js';

// TODO shoud models be pre sorted?
// Maybe! But I don't know if I want to rely on that?
const sortArr = (arr: any[]) => {
  arr.sort((a, b) => {
    const astr = typeof a === 'string' ? a : a.name;
    const bstr = typeof b === 'string' ? b : b.name;

    if (astr === bstr) return 0;
    if (astr > bstr) {
      return 1;
    } else {
      return -1;
    }
  });
  return arr;
};

const sortDeep = (model: any) => {
  if (model.children) {
    if (Array.isArray(model.children)) {
      model.children = sortArr(model.children.map(sortDeep));
    } else {
      const keys = Object.keys(model.children).sort();
      model.children = keys.reduce((acc, key) => {
        acc[key] = sortArr(model.children[key].map(sortDeep));
        return acc;
      }, {});
    }
  }
  return model;
};

const loadMetadata = ctx =>
  new Promise<object>(resolve => {
    const callbackRef = ctx.handleEvent('metadata_ready', data => {
      ctx.removeHandleEvent(callbackRef);
      resolve(data);
    });

    ctx.pushEventTo(ctx.el, 'request_metadata', {});
  });

// // Temporary fake metadata loader
// new Promise<object>(resolve => {
//   let metadata = null;
//   // TODO what if the metadata changes in flight?
//   // May need to double check the adaptor value
//   if (adaptor) {
//     if (adaptor.match('dhis2')) {
//       metadata = sortDeep(metadata_dhis2);
//     } else if (adaptor.match('salesforce')) {
//       metadata = sortDeep(metadata_salesforce);
//     }
//   }
//   setTimeout(() => {
//     resolve(metadata);
//   }, 1000 * 5);
// });

export default loadMetadata;
