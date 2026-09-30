# Show custom data on Homepage

Homepage can display data from a JSON file with its built-in `customapi` service widget, provided a web server serves the file over HTTP. Its `dynamic-list` display is useful for a compact set of rows (a name and one value per row). Homepage does not provide a config-only widget for rendering an arbitrary HTML table; for several columns per row or a specific table layout, you need to build a custom Homepage widget.

## Example: household items

This repo includes a working sample. The file [household-items.json](../containers/homepage/static-data/household-items.json) contains:

```json
{
  "items": [
    { "name": "Coffee", "location": "Pantry" },
    { "name": "Rice", "location": "Pantry" },
    { "name": "Batteries", "location": "Utility drawer" }
  ]
}
```

The `homepage-data` Nginx service in `containers/homepage/docker-compose.yml` serves that folder inside the Compose network. Homepage's service entry in `containers/homepage/config/services.yaml` fetches `http://homepage-data/household-items.json`:

```yaml
- Home:
    - Household items:
        icon: mdi-home
        widget:
          type: customapi
          url: http://homepage-data/household-items.json
          refreshInterval: 60000
          display: dynamic-list
          mappings:
            items: items
            name: name
            label: location
```

The widget shows Coffee, Rice, and Batteries as rows, with their location beside each name. In the browser, the sample looks like:

```text
Household items
Coffee                           Pantry
Rice                             Pantry
Batteries                        Utility drawer
```

To add your own data, edit `containers/homepage/static-data/household-items.json` and keep the same JSON shape, or change the `mappings` in `services.yaml` to match your fields. The deployment config copies `static-data/` to `${CONTAINERS_DATA}/static-data` on the host, and Nginx serves it read-only. The URL must be reachable **from the Homepage container**; `homepage-data` resolves to the sidecar because both services share the Compose network.

The `mappings` options point the widget to the `items` array and identify which fields appear on each row. For custom nested objects or more options, check the current [Custom API widget documentation](https://gethomepage.dev/widgets/services/customapi/). For a fully custom visual component, Homepage's [widget authoring guide](https://gethomepage.dev/widgets/authoring/tutorial/) describes building and registering a widget in a Homepage source build; adding files to this repo's config volume alone cannot register a new widget.

After changing the JSON file, redeploy the Homepage container so the updated file is copied to the host. After changing `services.yaml`, redeploy or restart Homepage so it reloads the config. The guide's sample uses the existing deployment flow and adds an Nginx sidecar to serve the static file.
