// Small helpers shared by the route files.

// An error that carries the HTTP status code to send back.
class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// Turn a URL or body value into a positive whole number, or reply 400.
function toId(value, label = 'id') {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1) {
    throw new HttpError(400, `${label} must be a positive whole number.`);
  }
  return n;
}

// Turn a price or quantity into a number that is zero or more, or reply 400.
function toAmount(value, label) {
  const n = Number(value);
  if (value === '' || value === null || !Number.isFinite(n) || n < 0) {
    throw new HttpError(400, `${label} must be a number of zero or more.`);
  }
  return n;
}

// Reply 400 if any of the named fields is missing from the request body.
function requireFields(body, fields) {
  const missing = fields.filter(f => body[f] === undefined || body[f] === null || body[f] === '');
  if (missing.length) {
    throw new HttpError(400, `Missing field(s): ${missing.join(', ')}.`);
  }
}

// Reply 404 if a lookup found nothing.
function found(row, what) {
  if (!row) throw new HttpError(404, `${what} not found.`);
  return row;
}

module.exports = { HttpError, toId, toAmount, requireFields, found };
