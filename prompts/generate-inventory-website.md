You are turning a completed infrastructure inventory Markdown file into a clear,
readable static website.

## Input and output

- The user will provide the path to one Markdown inventory file.
- Read that file as the sole source of inventory facts. Do not scan the repository
  or consult other files to fill gaps.
- Create a sibling output directory named after the input file without its `.md`
  extension. For example, for
  `temp-data/inventory-20260920-203522.md`, write the website to
  `temp-data/inventory-20260920-203522/`.
- Put the complete website in that directory, with `index.html` as its entry
  point. Keep the site self-contained: use local HTML, CSS, and JavaScript only,
  with no remote fonts, scripts, stylesheets, images, analytics, or build tools.
- Do not modify the input Markdown file or any other files. If the output directory
  already exists, inspect its contents and update only files needed for this site;
  preserve unrelated files.

## Content and accuracy

- Preserve the inventory's facts, qualifications, uncertainty, and distinctions
  between configured, documented, inferred, and unknown values.
- Do not invent, infer, or look up missing information. Do not claim a service is
  running unless the inventory explicitly says so.
- Do not add secret values or expose any sensitive information. If the input
  appears to contain credentials, tokens, private keys, or passwords, omit their
  values from the website and indicate that sensitive content was omitted.
- Keep all meaningful inventory sections and entries. Organize them for quick
  scanning, with a clear hierarchy, concise labels, and useful cross references
  where the source supports them.

## Presentation

- Build a polished, responsive site that works on desktop and mobile and remains
  readable with keyboard navigation and assistive technology.
- Start with the inventory title and generated-at information when present.
- Add a compact overview of the important information available in the source,
  such as service and server counts, notable mismatches, or unknowns. Derive
  counts only from entries that are explicitly present, and do not suggest
  operational status.
- Give major inventory sections distinct visual sections. Use semantic headings,
  readable tables for comparison or repeated structured facts, and cards or lists
  where they make details easier to scan. Ensure wide tables remain usable on
  narrow screens.
- Include in-page navigation for the major sections. If useful, add lightweight
  client-side filtering for long lists, while keeping all content accessible when
  JavaScript is unavailable.
- Use a restrained visual style with strong contrast, consistent spacing, and
  clear distinction for documentation-only, inferred, unknown, or mismatched
  details when those distinctions occur in the inventory.
- Escape source text safely when placing it in HTML. Do not interpret inventory
  content as executable HTML or JavaScript.

After creating the site, report the output directory and briefly list the files
created or updated.
