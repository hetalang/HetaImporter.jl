using Documenter
using HetaImporter

makedocs(
  modules = [HetaImporter],
  sitename = "HetaImporter.jl",
  format = Documenter.HTML(
    prettyurls = get(ENV, "CI", "false") == "true",
    canonical = "https://hetalang.github.io/HetaImporter.jl/",
    edit_link = nothing,
    repolink = "https://github.com/hetalang/HetaImporter.jl"
  ),
  pages = [
    "Home" => "index.md",
    "API" => "api.md"
  ],
  remotes = nothing,
  checkdocs = :exports
)
