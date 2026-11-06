# Android Google Maps API keys

The app injects the Maps key via the `GOOGLE_MAPS_ANDROID_API_KEY` manifest placeholder.

- **Production (`prod` flavor):** The production key is set in `android/app/build.gradle.kts` `defaultConfig` and must stay **byte-for-byte** unchanged for store builds.
- **Development (`dev` flavor):** Use the tashil-dev key named **Dev Maps Android key** (GCP project `tashil-dev`, restricted to `com.tashil.delegate.dev` and your debug SHA-1). Provide it **only** via local config — do not commit the value.

## Local setup (dev flavor)

Pick one:

1. **Environment variable** (CI or your shell):

   ```bash
   export DEV_MAPS_ANDROID_KEY='<paste Dev Maps Android key from GCP>'
   ```

2. **`local.properties`** (gitignored; same directory as this file):

   ```properties
   devMapsAndroidKey=AIza...your-dev-key...
   ```

Building **`dev`** requires the key to be set; otherwise Gradle fails fast with a clear message.

## Lookup (GCP)

If you have [`gcloud`](https://cloud.google.com/sdk/docs/install) authenticated to `tashil-dev`:

```bash
gcloud services api-keys list --project=tashil-dev --filter='displayName:"Dev Maps Android key"'
# Then get the key string (do not paste into committed files):
gcloud services api-keys get-key-string API_KEY_RESOURCE_NAME --project=tashil-dev
```

Never print the full key in CI logs or commit history.
