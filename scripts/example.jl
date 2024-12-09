# include("../src/StdEcgStats.jl")
# using .StdEcgStats

# using OrderedCollections, JSON3


### пример использования

### для STDECGDB с параметрами коммандной строки
### получение таблиц статистики
cmd = `julia --project=@. --startup-file=no`
cmd = `$cmd deploy/run_app.jl calc --ref_author skv --test_author box51_v2 --keyset_file keys2find`
run(cmd);

### сравнение таблиц статистики
cmd = `julia --project=@. --startup-file=no`
cmd = `$cmd deploy/run_app.jl compare --old_tables_path "box51_VS_skv_2024-12-09T14-26-18" --new_tables_path "box51_VS_skv_2024-12-09T15-14-15"`
run(cmd)

# ### произвольно
# rootdir = "Y:/skv/STDECGDB"
# binpath = joinpath(rootdir, "bin")
# markpath = joinpath(rootdir, "mkp")

# ref_author = "0"
# test_author = "box51_v2"

# keys2find = JSON3.read(joinpath(@__DIR__, "../keys2find.json"), OrderedDict{String, OrderedDict{String, String}})

# StdEcgStats.compare_markups(binpath, markpath, joinpath(@__DIR__, "../tables"), ref_author, test_author, keys2find)
