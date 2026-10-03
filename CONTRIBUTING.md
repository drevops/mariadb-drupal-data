# Contributing

Thank you for considering a contribution to this project. This guide covers setting up a local environment and running the linting and tests.

## Local setup

You'll need Docker, Node.js, `shfmt` and `shellcheck`. Install the BATS test dependencies:

```shell
npm --prefix tests/bats ci
```

## Linting

```shell
shfmt -i 2 -ci -s -d seed.sh tests/bats/*.bash tests/bats/*.bats
shellcheck seed.sh tests/bats/*.bash tests/bats/*.bats
```

## Testing

```shell
tests/bats/node_modules/.bin/bats tests/bats
```

The tests copy the repository at its last commit, so commit your changes before running them. The seeding tests push images to `drevops/mariadb-drupal-data-test` on Docker Hub, so run `docker login` with an account that can push there.
