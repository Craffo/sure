# Personal fork

This branch starts from upstream `v0.7.5-hotfix.1` (commit
`789883081feda49fcfa8c7bc923cc77c9fe301ad`). `origin` is the personal fork;
`upstream` is `we-promise/sure`.

The dashboard cash-flow widget reuses the hierarchy-aware Sankey calculation.
It shows up to six expense categories and three income categories, groups the
remainder, and lists all categories and subcategories in an expandable table.
Income, spending and their difference are explicit. A deficit supplies the
missing flow when spending exceeds income; it is not labeled as earned income.
Grouping changes presentation only and writes no financial records.

`Dockerfile.personal` builds on the exact upstream release image, copies the
fork's application code and translations, and rebuilds assets. It is deliberately
tied to this release's dependencies. When updating Rails, gems or the database,
use the full upstream Dockerfile and review the release's migration procedure.

Keep installation configuration, bank exports, backups, credentials and all real
financial information outside this repository. Build with:

```sh
docker build -f Dockerfile.personal -t sure-personal:cashflow-overview .
```

Use that image for both the web and worker services in the private deployment's
Compose override. Existing database and storage volumes remain in place. To
roll back this presentation-only change, select the original pinned upstream
image for both services and recreate them; no database rollback is required.

Before updating the fork, fetch upstream tags, review the release changes, and
merge the chosen tag into this branch. Re-run the tests and rebuild the image.
Do not automatically update to upstream's moving default branch.
