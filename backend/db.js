// Connection to SQL Server, using your Windows login (no password needed).
// Change the server or database with environment variables, e.g.
//   DB_SERVER=.\SQLEXPRESS  DB_NAME=shopsphere
const sql = require('mssql/msnodesqlv8');

const server = process.env.DB_SERVER || '.\\SQLEXPRESS';
const database = process.env.DB_NAME || 'shopsphere';
const driver = process.env.DB_DRIVER || 'ODBC Driver 18 for SQL Server';

const pool = new sql.ConnectionPool({
  connectionString:
    `Driver={${driver}};Server=${server};Database=${database};` +
    'Trusted_Connection=yes;TrustServerCertificate=yes;',
});
const ready = pool.connect();

// Run a SQL query. Every value goes in as a parameter (@name), never
// pasted into the SQL text, so user input cannot break the query.
//   await query('SELECT * FROM Product WHERE ProductID = @id', { id: 5 })
async function query(text, params = {}) {
  await ready;
  const request = pool.request();
  for (const [name, value] of Object.entries(params)) request.input(name, value ?? null);
  const result = await request.query(text);
  return result.recordset || [];
}

// Run a stored procedure and return the rows it selects.
//   await execute('sp_AddToCart', { CustomerID: 1, VariantID: 3, Quantity: 1 })
async function execute(procedure, params = {}) {
  await ready;
  const request = pool.request();
  for (const [name, value] of Object.entries(params)) request.input(name, value ?? null);
  const result = await request.execute(procedure);
  return result.recordset || [];
}

module.exports = { query, execute, ready, server, database };
