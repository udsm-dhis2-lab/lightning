export default specifier => {
  const [prefix, name] = specifier.match(/@openfn.language-(.+)@/);
  return name || 'unknown';
};
