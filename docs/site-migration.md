# Website Repository Migration

This app repository no longer contains the website source.
The site history has been prepared in branch `site-split`.

## Push Site to a New Repository

1. Create a new empty GitHub repository for the website.
2. Push the prepared branch:

```bash
git push <site-repo-url> site-split:main
```

Example:

```bash
git push https://github.com/altansaid/qdock-site.git site-split:main
```

## Optional Local Clone for Site-Only Work

```bash
git clone <site-repo-url> qdock-site
cd qdock-site
```
