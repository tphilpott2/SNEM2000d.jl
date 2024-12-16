using SNEM2000d
using Documenter

DocMeta.setdocmeta!(SNEM2000d, :DocTestSetup, :(using SNEM2000d); recursive=true)

makedocs(;
    modules=[SNEM2000d],
    authors="tom philpott <tsp266@uowmail.edu.au> and contributors",
    sitename="SNEM2000d.jl",
    format=Documenter.HTML(;
        canonical="https://tphilpott2.github.io/SNEM2000d.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/tphilpott2/SNEM2000d.jl",
    devbranch="main",
)
