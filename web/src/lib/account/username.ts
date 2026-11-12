/** The characters a username may not have (only a–z, 0–9 and _), each once. */
export const badChars = (name: string) => [...new Set(name.replace(/[a-z0-9_]/g, ''))];
