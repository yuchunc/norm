defmodule Norm.Schema do
  @moduledoc false
  # Provides the definition for schemas

  alias __MODULE__
  alias Norm.Spec

  defstruct specs: [], struct: nil

  # If we're building a schema from a struct then we need to add a default spec
  # for each key that only checks for presence. This allows users to specify
  # struct types without needing to specify specs for each key
  def build(%{__struct__: name}=struct) do
    specs =
      struct
      |> Map.from_struct
      |> Enum.to_list()
      |> Enum.filter(fn {_key, spec} -> match?(%Spec{}, spec) end)

    %Schema{specs: specs, struct: name}
  end

  def build(map) when is_map(map) do
    specs =
      map
      |> Enum.to_list()

    %Schema{specs: specs}
  end

  defimpl Norm.Conformer.Conformable do
    alias Norm.Conformer.Conformable

    def conform(_, input, path) when not is_map(input) do
      {:error, [error(path, input, "not a map")]}
    end

    def conform(%{specs: specs, struct: struct}, input, path) when not is_nil(struct) do
      if Map.get(input, :__struct__) == struct do
        check_specs(specs, input, path)
      else
        short_name =
          struct
          |> Atom.to_string
          |> String.replace("Elixir.", "")

        {:error, [error(path, input, "#{short_name}")]}
      end
    end

    def conform(%Norm.Schema{specs: specs}, input, path) do
      check_specs(specs, input, path)
    end

    defp check_specs(specs, input, path) do
      errors =
        specs
        |> Enum.map(fn {key, spec} ->
          val = Map.get(input, key)

          if val do
            {key, Conformable.conform(spec, val, path ++ [key])}
          else
            {key, {:error, [error(path ++ [key], input, ":required")]}}
          end
        end)
        |> Enum.filter(fn {_, {result, _}} -> result == :error end)
        |> Enum.flat_map(fn {_, {_, errors}} -> errors end)

      if Enum.any?(errors) do
        {:error, errors}
      else
        {:ok, input}
      end
    end

    defp error(path, input, msg) do
      %{path: path, input: input, msg: msg, at: nil}
    end
  end

  defimpl Norm.Generatable do
    alias Norm.Generatable

    def gen(%{specs: specs}) do
      case Enum.reduce(specs, %{}, &to_gen/2) do
        {:error, error} ->
          {:error, error}

        generator ->
          {:ok, StreamData.fixed_map(generator)}
      end
    end

    def to_gen(_, {:error, error}), do: {:error, error}
    def to_gen({key, spec}, generator) do
      case Generatable.gen(spec) do
        {:ok, g} ->
          Map.put(generator, key, g)

        {:error, error} ->
          {:error, error}
      end
    end
  end
end
