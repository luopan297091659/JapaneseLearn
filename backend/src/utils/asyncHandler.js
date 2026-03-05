// wrapper to avoid repetitive try/catch blocks in controllers
module.exports = fn => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};
