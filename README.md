# hl-component-sftp CfHighlander project
---

## Cfhighlander Setup

install cfhighlander [gem](https://github.com/theonestack/cfhighlander)

```bash
gem install cfhighlander
```

or via docker

```bash
docker pull theonestack/cfhighlander
```

compiling the templates

```bash
cfcompile sftp
```

compiling with the vaildate fag to validate the templates

```bash
cfcompile sftp --validate
```

publish the templates to s3

```bash
cfpublish sftp --version latest
```
