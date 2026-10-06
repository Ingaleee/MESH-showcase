import { test } from "@playwright/test";

const attempts: number[] = [];
const windowMs = 180000;

// Browser contexts share the local proxy IP. Respect its real 15/3-min limit.
// Leave three slots for an occasional manual login and never disable the guard.
export async function reserveLogin() {
  const now = Date.now();
  while (attempts.length && attempts[0] <= now - windowMs) attempts.shift();
  if (attempts.length >= 12) {
    const wait = attempts[0] + windowMs - now + 1000;
    const info = test.info();
    info.setTimeout(info.timeout + wait);
    await new Promise((resolve) => setTimeout(resolve, wait));
    return reserveLogin();
  }
  attempts.push(Date.now());
}
