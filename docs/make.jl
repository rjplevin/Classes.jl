using Documenter, Classes

makedocs(
    modules = [Classes],
	sitename = "Classes.jl",
	pages = [
		"Home" => "index.md",
	],

	format = Documenter.HTML(prettyurls = get(ENV, "JULIA_NO_LOCAL_PRETTY_URLS", nothing) === nothing)
)

deploydocs(
    repo = "github.com/rjplevin/Classes.jl.git",
)
