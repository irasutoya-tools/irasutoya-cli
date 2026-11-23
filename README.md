# Irasutoya::Cli

[![CI](https://github.com/irasutoya-tools/irasutoya-cli/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/irasutoya-tools/irasutoya-cli/actions/workflows/test.yml)
[![Gem Version](https://badge.fury.io/rb/irasutoya-cli.svg)](https://badge.fury.io/rb/irasutoya-cli)
[![Code Climate](https://codeclimate.com/github/irasutoya-tools/irasutoya-cli/badges/gpa.svg)](https://codeclimate.com/github/irasutoya-tools/irasutoya-cli)
[![codecov](https://codecov.io/gh/irasutoya-tools/irasutoya-cli/branch/master/graph/badge.svg)](https://codecov.io/gh/irasutoya-tools/irasutoya-cli)
[![Libraries.io dependency status for GitHub repo](https://img.shields.io/librariesio/github/irasutoya-tools/irasutoya-cli.svg)](https://libraries.io/github/irasutoya-tools/irasutoya-cli)
![](http://ruby-gem-downloads-badge.herokuapp.com/irasutoya-cli?type=total)
![GitHub](https://img.shields.io/github/license/irasutoya-tools/irasutoya-cli.svg)

![](./images/example.png)

## Installation

Ruby 3.3 or newer is required.

```sh
$ gem install irasutoya-cli
```

## Quick Start

After installing the gem, run a search with a single query argument:

```sh
$ irasutoya search '猫'
```

Run `irasutoya random` to browse a randomly selected illustration or
`irasutoya help` to list the commands available in your installed version.

## Download images from a checkout

The `download` command requires a checkout when using the 1.0.1 release.
Install the Ruby version in [.ruby-version](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/.ruby-version)
and the Bundler version under `BUNDLED WITH` in [Gemfile.lock](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/Gemfile.lock), then run:

```sh
$ git clone https://github.com/irasutoya-tools/irasutoya-cli.git
$ cd irasutoya-cli
$ bundle install
```

Copy the `Page URL` from a search or random result and substitute it for
`PAGE_URL`:

```sh
$ bundle exec exe/irasutoya download 'PAGE_URL' --output ./images
```

Choose an `--output` directory on a filesystem that supports hard links. The command uses hard links to save images, so a FAT32 destination will fail even if it is writable.

The command creates the destination directory if needed, saves every image on the page, and prints each saved path. If a filename is already taken, the command adds a numeric suffix before the extension. Downloads work in terminals without inline preview support.

Each image download is limited to 10 MiB (10,485,760 bytes). If an image exceeds the limit, the command stops and discards that download. Images already saved are kept.

See the [CLI reference](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/docs/usage.md)
for checkout command arguments, output, and preview behavior.
See [FAQ and troubleshooting](https://github.com/irasutoya-tools/irasutoya-cli/blob/master/docs/troubleshooting.md)
for help with missing commands, previews, and download destinations.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/irasutoya-tools/irasutoya-cli. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Irasutoya::Cli project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/unhappychoice/irasutoya-cli/blob/master/CODE_OF_CONDUCT.md).

## Author

[@unhappychoice](https://unhappychoice.com)
