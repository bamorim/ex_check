defmodule Mix.Tasks.Check do
  @moduledoc """
  One task to efficiently run all code analysis & testing tools in an Elixir project.

  ## Tools

  Task comes out of the box with a rich predefined set of curated tools that are considered to be
  reasonable additions for most Elixir and Phoenix projects which care about having bug-free,
  maintainable and secure code.

  Following curated tools are configured by default:

  - [`:compiler`] - produces compilation warnings that allow to early detect bugs & typos in the
    code eg. an attempt to call non-existing or deprecated function

  - [`:formatter`] - ensures that all the code follows the same basic formatting rules such as
    maximum number of chars in a line or function indentation

  - [`:ex_unit`] - starts the application in test mode and runs all runtime tests against it
    (defined as test modules or embedded in docs as doctests)

  - [`:credo`] - ensures that all the code follows a further established set of software design,
    consistency, readability & misc rules and conventions (still statical)

  - [`:sobelow`] - performs security-focused static analysis mainly focused on the Phoenix
    framework, but also detecting vulnerable dependencies in arbitrary Mix projects

  - [`:dialyzer`] - performs static code analysis around type mismatches and other issues that are
    commonly detected by static language compilers

  - [`:ex_doc`] - compiles the project documentation in order to ensure that there are no issues
    that would make it impossible for docs to get collected and assembled

  - [`:npm_test`] - runs JavaScript tests in projects with front-end assets embedded in `assets`
    directory and `package.json` in it (default for Phoenix apps)

  - [`:unused_deps`] - ensures that there are no unused dependencies in the project's `mix.lock`
    file (e.g. after removing a previously used dependency)

  You can disable or adjust curated tools as well as add custom ones via the configuration file.

  ## Workflow

  1. `:compiler` tool is run before others in order to compile the project just once and to avoid
     reprinting the compilation error multiple times.

  2. If the compilation succeded (even if with warnings), further tools are run in parallel while
     their output is streamed live one by one for instant insight.

  3. Output from tools that have failed gets reprinted for sake of easily reading into them all at
     once and identifying all project issues in one go.

  4. Summary is presented with a list of all tools that have failed, succeeded or were skipped due
     to missing files or project dependencies.

  5. If any of the tools have failed, the Erlang system gets requested to emit exit status 1 upon
     shutdown in order to make the CI build fail.

  ### Tool order

  Tools are run in parallel, but their output is presented one by one in order to avoid mixing it
  up. You can control the order in which the output is presented for tools that have started at the
  same time via the `:order` tool option. You'll probably want to put tools that run quicker and
  fail more often before the others in order to get useful feedback as soon as possible. Curated
  tools are ordered in such a way out of the box.

  ### Tool processes and ANSI formatting

  Tools are run in separate processes. This has following benefits:

  - allows to run tools in parallel & stream their output
  - catches exit statuses in order to detect failures
  - enables running Mix tasks in multiple envs
  - enables including non-Elixir scripts and tools in the check

  The downside is that tools will be run outside of TTY which will usually result in disabling ANSI
  formatting. This issue is fixed in different ways depending on Elixir version:

  - **Elixir 1.9 and newer**: patches all Elixir commands and Mix tasks with `--erl-config` option
    to load the Erlang configuration provided by `ex_check` that sets the `ansi_enabled` flag

  - **older versions**: patches Mix tasks with `--eval` option to run `Application.put_env/3` that
    sets the `ansi_enabled` flag

  You may keep your Elixir commands unaffected via the `:enable_ansi` tool option. It's ignored for
  non-Elixir tools for which you'll have to enforce ANSI on your own.

  ### Cross-tool dependencies

  Even though tools are run in parallel, it's possible to make sure that specific tool will be run
  only after other(s) are completed via the `:deps` tool option. This enables defining complex
  workflows, such as the following:

  - tools may reuse artifacts from ones executed earlier
  - tools may handle the success/failure of those they depend on
  - tools may be forced not to run at the same time without giving up on entire parallel execution

  By default tools will be run regardless of the exit status of their dependencies, but it's
  possible to depend on specific exit status via the `:status` dependency option. Tools will not be
  run if their dependencies won't get to run at all e.g. due to using `--except` command line option
  or a missing/circular dependency.

  ### Umbrella projects

  Task comes with extensive support for umbrella projects. The most notable feature is the ability
  to run tools recursively for each child app separately. It's similar to flagging Mix tasks as
  recursive but empowered with following extra benefits:

  - runs recursively not just Mix tasks, but also arbitrary scripts & commands
  - runs tools on child apps in parallel
  - allows tools to target only specific child apps
  - presents failures & run durations for each child app separately
  - detects if curated tools should run for each child app separately
  - builds separate cross-tool dependency chains for each child app

  You may want to disable parallel execution of the tool on child apps (`parallel: false` under
  `:umbrella` tool option) if it uses the same resources across tool runs against different child
  apps. An example of that could be `ex_unit` that, depending on a project and test dependencies,
  may involve mutating the same database in test suites belonging to separate child apps.

  You may have the tool run *only* at the root level of the umbrella by disabling the recursive
  execution (`recursive: false` under `:umbrella` tool option) and targeting an empty list of child
  apps (`apps: []` under `:umbrella` tool option).

  ## Configuration file

  Check configuration may be adjusted with the optional `.check.exs` file.

  Configuration file should evaluate to keyword list with following options:

  - `:parallel` - toggles running tools in parallel; default: `true`
  - `:skipped` - toggles printing skipped tools in summary; default: `true`
  - `:tools` - a list of tools to run; default: curated tools; more info below

  Tool list under `:tools` key may contain following tool tuples:

  - `{:tool_name, opts}`
  - `{:tool_name, enabled}` where `enabled` corresponds to the `:enabled` option
  - `{:tool_name, command}` where `command` corresponds to the `:command` option
  - `{:tool_name, command, opts}` where `command` corresponds to the `:command` option

  Tool options (`opts` above) is a keyword list with following options:

  - `:enabled` - enables/disables already defined tools; default: `true`
  - `:command` - command as string or list of strings (executable + arguments)
  - `:cd` - directory (relative to cwd) to change to before running the command
  - `:env` - environment variables as map with string keys & values
  - `:order` - integer that controls the order in which tool output is presented; default: `0`
  - `:deps` - list of tools that the given tool depends on; more info below
  - `:enable_ansi` - toggles extending Elixir/Mix commands to have ANSI enabled; default: `true`
  - `:umbrella` - configures the tool behaviour in an umbrella project; more info below

  Dependency list under `:deps` key may contain `:tool_name` atoms or `{:tool_name, opts}` tuples
  where `opts` is a keyword list with following options:

  - `:status` - depends on specific exit status; one of `:ok`, `:error`, exit code integer or a list
    with any of the above; default: any exit status
  - `:else` -  specifies the behaviour upon dependency being unsatisfied; one of `:skip` (show the
    tool among skipped ones), `:disable` (disable the tool without notice); default: `:skip`

  Umbrella configuration under `:umbrella` key is a keyword list with following options:

  - `:recursive` - toggles running the tool on each child app separately as opposed to running it
    once from umbrella root; default: `true` except for non-recursive Mix tasks
  - `:parallel` - toggles running tool in parallel on all child apps; default: `true`
  - `:apps` - list of umbrella child app names targeted by the tool; default: all apps

  Task will load the configuration in following order:

  1. Default stock configuration.
  2. `--config` file opt on command line.
  3. `.check.exs` in user home directory.
  4. `.check.exs` in current project directory (or umbrella root for an umbrella project).

  Use the `mix check.gen.config` task to generate sample configuration that comes with well-commented examples to help you get started.

  ## Command line options

  - `--config /some/file` - Override default config file
  - `--only dialyzer --only credo ...` - run only specified check(s)
  - `--except dialyzer --except credo ...` - don't run specified check(s)
  - `--no-parallel` - don't run tools in parallel
  - `--no-skipped` - don't print skipped tools in summary

  [`:compiler`]: https://hexdocs.pm/mix/Mix.Tasks.Compile.html
  [`:formatter`]: https://hexdocs.pm/mix/Mix.Tasks.Format.html
  [`:ex_unit`]: https://hexdocs.pm/ex_unit
  [`:credo`]: https://hexdocs.pm/credo
  [`:sobelow`]: https://hexdocs.pm/sobelow
  [`:dialyzer`]: https://hexdocs.pm/dialyxir
  [`:ex_doc`]: https://hexdocs.pm/ex_doc
  [`:npm_test`]: https://docs.npmjs.com/cli/test.html
  [`:unused_deps`]: https://hexdocs.pm/mix/Mix.Tasks.Deps.Unlock.html
  """

  use Mix.Task
  alias ExCheck.Check

  @shortdoc "Runs all code analysis & testing tools in an Elixir project"

  @preferred_cli_env :test

  @switches [
    only: :keep,
    except: :keep,
    skipped: :boolean,
    exit_status: :boolean,
    parallel: :boolean,
    config: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches)

    opts
    |> process_opts()
    |> Check.run()
  end

  defp process_opts(opts) do
    Enum.map(opts, fn
      {:only, name} -> {:only, String.to_atom(name)}
      {:except, name} -> {:except, String.to_atom(name)}
      opt -> opt
    end)
  end
end
