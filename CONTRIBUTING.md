# Contributing

Bug reports and pull requests are welcome. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Set up your development environment

Install the Ruby version listed in [.ruby-version](.ruby-version) and the
Bundler version listed under `BUNDLED WITH` in [Gemfile.lock](Gemfile.lock).
Then clone the repository and install its dependencies.

```sh
git clone https://github.com/irasutoya-tools/irasutoya-cli.git
cd irasutoya-cli
bundle install
```

Run the CLI from your checkout with `bundle exec exe/irasutoya help`.
See the [CLI architecture guide](docs/architecture.md) for where to start reading the code.

## Run the checks

```sh
bundle exec rubocop lib
COVERAGE=true bundle exec rspec
test -s coverage/coverage.xml
```

## Open a pull request

Fork the repository if needed, create a branch from `master`, and keep your
changes focused. Add or update tests when you change behavior. Push your
branch and open a pull request against `irasutoya-tools/irasutoya-cli:master`.
Describe what changed and include the checks you ran.

## Release a gem

Update the version in `lib/irasutoya/cli/version.rb` and add the release entry
to [CHANGELOG.md](CHANGELOG.md). Once those changes are on `master`, push a
`vMAJOR.MINOR.PATCH` tag for that commit. The release workflow checks the tag
against the gemspec version, builds the gem, and publishes it to RubyGems.org.
