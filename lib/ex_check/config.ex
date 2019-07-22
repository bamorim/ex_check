defmodule ExCheck.Config do
  @moduledoc false

  alias ExCheck.{Printer, Project}

  @curated_tools [
    {:compiler, command: "mix check.run compile --warnings-as-errors --force"},
    {:formatter,
     command: "mix check.run format --check-formatted", require_files: [".formatter.exs"]},
    {:ex_unit, command: "MIX_ENV=test mix check.run test", require_files: ["test/test_helper.exs"]},
    {:credo, command: "mix check.run credo", require_deps: [:credo]},
    {:sobelow, command: "mix check.run sobelow --exit --skip", require_deps: [:sobelow]},
    {:dialyzer, command: "mix check.run dialyzer --halt-exit-status", require_deps: [:dialyxir]},
    {:ex_doc, command: "mix check.run docs", require_deps: [:ex_doc]}
  ]

  @default_config [
    parallel: true,
    exit_status: true,
    skipped: true,
    tools: @curated_tools
  ]

  @option_list [:parallel, :exit_status, :skipped]

  @config_filename ".check.exs"

  def get_opts(config) do
    Keyword.take(config, @option_list)
  end

  def get_tools(config) do
    Keyword.fetch!(config, :tools)
  end

  # sobelow_skip ["RCE.CodeModule"]
  def load do
    user_home_dir = System.user_home()
    user_dirs = if user_home_dir, do: [user_home_dir], else: []
    project_dirs = Project.get_mix_parent_dirs()
    dirs = user_dirs ++ project_dirs

    Enum.reduce(dirs, @default_config, fn next_config_dir, config ->
      next_config_filename =
        next_config_dir
        |> Path.join(@config_filename)
        |> Path.expand()

      if File.exists?(next_config_filename) do
        {next_config, _} = Code.eval_file(next_config_filename)
        merge_config(config, next_config)
      else
        config
      end
    end)
  end

  defp merge_config(config, next_config) do
    config_opts = Keyword.take(config, @option_list)
    next_config_opts = Keyword.take(next_config, @option_list)
    merged_opts = Keyword.merge(config_opts, next_config_opts)

    config_tools = Keyword.fetch!(config, :tools)
    next_config_tools = Keyword.get(next_config, :tools, [])

    merged_tools =
      Enum.reduce(next_config_tools, config_tools, fn next_check, tools ->
        next_check_name = elem(next_check, 0)
        check = List.keyfind(tools, next_check_name, 0)
        merged_check = merge_check(check, next_check)
        List.keystore(tools, next_check_name, 0, merged_check)
      end)

    Keyword.put(merged_opts, :tools, merged_tools)
  end

  defp merge_check(check, next_check)
  defp merge_check(nil, next_check), do: next_check
  defp merge_check({name, false}, next_check = {name, _}), do: next_check
  defp merge_check({name, _}, next_check = {name, false}), do: next_check
  defp merge_check({name, opts}, {name, next_opts}), do: {name, Keyword.merge(opts, next_opts)}

  @generated_config """
  [
    ## all available options with default values (see `mix check` docs for description)
    # skipped: true,
    # exit_status: true,
    # parallel: true,

    ## list of tools (see `mix check` docs for defaults)
    tools: [
      ## curated tools may be disabled (e.g. the check for compilation warnings)
      # {:compiler, false},

      ## ...or adjusted (e.g. use one-line formatter for more compact credo output)
      # {:credo, command: "mix check.run credo --format oneline"},

      ## custom new tools may be added (mix tasks or arbitrary commands)
      # {:my_mix_check, command: "mix check.run some_task"},
      # {:my_other_check, command: "my_cmd"}
    ]
  ]
  """

  # sobelow_skip ["Traversal.FileModule"]
  def generate do
    target_path =
      Project.get_mix_root_dir()
      |> Path.join(@config_filename)
      |> Path.expand()

    formatted_path = Path.relative_to_cwd(target_path)

    if File.exists?(target_path) do
      Printer.info([:yellow, "* ", :bright, formatted_path, :normal, " already exists, skipped"])
    else
      Printer.info([:green, "* creating ", :bright, formatted_path])

      File.write!(target_path, @generated_config)
    end
  end
end
