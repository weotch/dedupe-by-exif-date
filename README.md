# dedupe-by-exif-date

A tool to clean up duplicates of media created by migration of Apple Photo Stream (or whatever) to Amazon photos.

```
$ coffee index.coffee 
coffee <keep> <remove> <trash>

Look for duplicates of media from the "keep" dir in the "remove" dir and move
them to the "trash" dir.

Positionals:
  keep    The directory of media to keep                                [string]
  remove  The directory of media whose duplicates will be removed       [string]
  trash   The directory that removed media will be moved to             [string]
```

## Install

1. Install Coffeescript
2. Setup a MySQL DB and install the `schema.sql`. Edit the index.coffee to add your connection creds.
3. Install node deps with `yarn install`