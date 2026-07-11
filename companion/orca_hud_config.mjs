function isPrivateIpv4(address) {
  return /^192\.168\.|^10\.|^172\.(1[6-9]|2\d|3[01])\./.test(address);
}

export function pickLanAddress(networks) {
  const addresses = Object.values(networks || {})
    .flat()
    .filter((item) => item && item.family === 'IPv4' && !item.internal)
    .map((item) => item.address)
    .filter(isPrivateIpv4);
  return addresses.find((address) => address.startsWith('192.168.')) || addresses[0] || null;
}

function luaString(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

export function renderConnectionLua({ host, port, token }) {
  return [
    'return {',
    `  base_url = "http://${luaString(host)}:${Number(port)}",`,
    `  token = "${luaString(token)}",`,
    '}',
    '',
  ].join('\n');
}
