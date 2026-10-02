# Contributing

Thank you for considering a contribution to this project. This guide covers
setting up a local environment and running the linting and tests.




    npm ci --prefix tests/bats
    shellcheck seed.sh tests/bats/*.bash tests/bats/*.bats
    shfmt -i 2 -ci -s -d seed.sh tests/bats/*.bash tests/bats/*.bats
    ./tests/bats/node_modules/.bin/bats tests/bats

