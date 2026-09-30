# Show custom data on Homepage

Homepage can display data from an HTTP JSON endpoint with its built-in `customapi` service widget. Its `dynamic-list` display is useful for a compact set of rows (a name and one value per row). Homepage does not provide a config-only widget for rendering an arbitrary HTML table; for several columns per row or a specific table layout, you need to build a custom Homepage widget.

## Example: household items

Suppose an API you control returns this JSON at `http://my-data-api:8080/household-items`:

```json
{
  "items": [
    { "name": "Coffee", "location": "Pantry" },
    { "name": "Rice", "location": "Pantry" },
    { "name": "Batteries", "location": "Utility drawer" }
  ]
}
```

Add this service to `containers/homepage/config/services.yaml`:

```yaml
- Home:
    - Household items:
        icon: mdi-home
        widget:
          type: customapi
          url: http://my-data-api:8080/household-items
          refreshInterval: 60000
          display: dynamic-list
          mappings:
            items: items
            name: name
            label: location
```

The widget will show Coffee, Rice, and Batteries as rows, with their location beside each name. The URL must be reachable **from the Homepage container**. If the API is another Compose service on the same Docker network, use its Compose service name as the hostname, as in this example. If the API runs elsewhere, use a hostname or IP address reachable from the container.

The `mappings` options point the widget to the `items` array and identify which fields appear on each row. For custom nested objects or more options, check the current [Custom API widget documentation](https://gethomepage.dev/widgets/services/customapi/). For a fully custom visual component, Homepage's [widget authoring guide](https://gethomepage.dev/widgets/authoring/tutorial/) describes building and registering a widget in a Homepage source build; adding files to this repo's config volume alone cannot register a new widget.

After changing `services.yaml`, redeploy or restart the Homepage container so it reloads the config. The example endpoint is illustrative: provide the JSON response from an API or small service you control.
