# QDock Landing Page

Single-page marketing and install page for QDock.

## Local Preview

```bash
cd site
python3 -m http.server 8080
```

Open `http://localhost:8080`.

## Deployment

The repository includes `.github/workflows/site.yml` for Vercel deployment.

Required secrets:

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`
