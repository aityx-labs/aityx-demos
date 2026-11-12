// tatyx on AWS Lambda (deploy/template.yaml): `handler` answers the API's
// function URL, behind CloudFront at /api/ and /aityx/, with the server's
// own `serve` (server.mjs), a function URL event made a Node request and
// the response made the event's answer; `runner` plays one tournament for
// the runner function (from the schedule, an admin or a new entry), one
// at a time. Never logs a body, a header or a cookie.

import { Readable } from 'node:stream';

import { leaderboard, serve } from './server.mjs';

/** The function URL's event as the server's request: method, URL, headers (the cookies one header again), body. */
function requestOf(event) {
  const http = event.requestContext?.http ?? {};
  const body = event.body === undefined || event.body === null ? Buffer.alloc(0) : Buffer.from(event.body, event.isBase64Encoded ? 'base64' : 'utf8');
  const request = Readable.from(body.length > 0 ? [body] : []);
  const headers = {};
  for (const [name, value] of Object.entries(event.headers ?? {})) headers[name.toLowerCase()] = value;
  if (Array.isArray(event.cookies) && event.cookies.length > 0) headers.cookie = event.cookies.join('; ');
  request.method = http.method ?? 'GET';
  request.url = `${event.rawPath ?? '/'}${event.rawQueryString ? `?${event.rawQueryString}` : ''}`;
  request.headers = headers;
  // The function URL is https, and so is CloudFront in front of it.
  request.socket = { encrypted: true };
  return request;
}

/** What the server answers, collected: the status, the headers (Set-Cookie apart, as the function URL takes cookies) and the body. */
function responseOf() {
  const headers = {};
  const cookies = [];
  const chunks = [];
  let done;
  const ended = new Promise((resolve) => (done = resolve));
  const response = {
    statusCode: 200,
    headersSent: false,
    setHeader(name, value) {
      if (name.toLowerCase() === 'set-cookie') cookies.push(...[value].flat());
      else headers[name.toLowerCase()] = String(value);
    },
    getHeader: (name) => headers[name.toLowerCase()],
    write(chunk) {
      response.headersSent = true;
      chunks.push(Buffer.from(chunk));
      return true;
    },
    end(chunk) {
      if (chunk !== undefined) chunks.push(Buffer.from(chunk));
      response.headersSent = true;
      done();
    },
  };
  return {
    response,
    answer: async () => {
      await ended;
      return { statusCode: response.statusCode, headers, cookies, body: Buffer.concat(chunks).toString('base64'), isBase64Encoded: true };
    },
  };
}

export async function handler(event) {
  const request = requestOf(event);
  const { response, answer } = responseOf();
  await serve(request, response);
  return answer();
}

/** One tournament, to its end: the event says who asked ({"source": "schedule"}, "admin", "strategy"). */
export async function runner(event) {
  const source = typeof event?.source === 'string' ? event.source : 'schedule';
  await leaderboard.runNow(source);
  return { ok: true };
}
