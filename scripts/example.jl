include("../src/StdEcgStats.jl")
using .StdEcgStats

using OrderedCollections, JSON3


### пример использования

### для STDECGDB с настройками через файл конфигурации (папка settings)
StdEcgStats.julia_main()

### произвольно
rootdir = "Y:/skv/STDECGDB"
binpath = joinpath(rootdir, "bin")
markpath = joinpath(rootdir, "mkp")

ref_author = "skv"
test_author = "box51_v2"

keys2find = JSON3.read(joinpath(@__DIR__, "../settings/keys2find.json"), OrderedDict{String, OrderedDict{String, String}})

StdEcgStats.compare_markups(binpath, markpath, joinpath(@__DIR__, "../tables"), ref_author, test_author, keys2find)
