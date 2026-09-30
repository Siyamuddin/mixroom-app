'use strict';

// Small evaluator for the pinned Scaler + LinearClassifier/TreeEnsembleRegressor
// graphs. Export-time validation rejects all other ONNX operators/attributes.
const MixInference = (() => {
  const f32 = Math.fround;
  function scaled(model, features) {
    if (features.length !== 77 || features.some(v => !Number.isFinite(v))) throw Error('feature_contract_mismatch');
    const xs = features.map((v, i) => f32(f32(f32(v) - model.offset[i]) * model.scale[i]));
    if (xs.some(v => !Number.isFinite(v))) throw Error('inference_nonfinite');
    return xs;
  }
  function classifier(model, features) {
    const xs = scaled(model, features);
    let score = model.intercepts[1];
    for (let i = 0; i < 77; i++) score += xs[i] * model.coefficients[77 + i];
    return f32(1 / (1 + Math.exp(-score)));
  }
  function regressor(model, features, tick = () => {}) {
    const xs = scaled(model, features);
    let total = 0;
    for (const tree of model.trees) {
      tick();
      let ix = 0, visited = 0;
      while (true) {
        if (++visited > tree.length) throw Error('model_graph_invalid');
        const node = tree[ix];
        if (!node) throw Error('model_graph_invalid');
        // [feature, threshold, true child, false child] or [leaf value].
        if (node.length === 1) { total += node[0]; break; }
        ix = xs[node[0]] <= node[1] ? node[2] : node[3];
      }
    }
    return f32(total + model.base);
  }
  function predict(bundle, features, tick = () => {}) {
    const applyScore = classifier(bundle.apply, features);
    const rawMagnitude = regressor(bundle.magnitude, features, tick);
    if (!Number.isFinite(applyScore) || !Number.isFinite(rawMagnitude)) throw Error('inference_nonfinite');
    return {applyScore, rawMagnitude};
  }
  return {scaled, classifier, regressor, predict};
})();
if (typeof module !== 'undefined') module.exports = MixInference;
