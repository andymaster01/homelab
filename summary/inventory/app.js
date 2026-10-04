"use strict";

const filter = document.querySelector("#service-filter");
const rows = [...document.querySelectorAll("#service-table tbody tr")];

if (filter) {
  filter.addEventListener("input", () => {
    const query = filter.value.trim().toLocaleLowerCase();
    for (const row of rows) {
      row.hidden = query !== "" && !row.textContent.toLocaleLowerCase().includes(query);
    }
  });
}
