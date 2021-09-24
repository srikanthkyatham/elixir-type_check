defmodule TypeCheck.Options.DefaultOverrides.Range do
  use TypeCheck
  @type! limit() :: integer()

  if Version.compare(System.version(), "1.12.0") == :lt do
    @type! t(first, last) :: %Elixir.Range{first: first, last: last}
  else
    @type! step() :: pos_integer() | neg_integer()

    @type! t(first, last) :: %Elixir.Range{first: first, last: last, step: step()}
  end

end
