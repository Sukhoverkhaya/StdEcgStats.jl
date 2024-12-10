module StdEcgStats

using JSON3, StructArrays
using ProgressMeter
using DataFrames
using FileUtils
using Statistics
using OrderedCollections
using Dates
using CSV
using ProgressMeter
import TimeSamplings: seg_outerjoin_indexpairs

using RelocatableFolders, ArgParse

include("CompareEvents.jl")
using .CompareEvents

include("CompareSegments.jl")
using .CompareSegments

include("CompareDurations51.jl")
using .CompareDurations51

include("CompareForms.jl")
using .CompareForms

#### Читалки/конверторы
include("readers.jl")
export read_markups

include("logical_calculator.jl")
include("keys2srch.jl")
export Keys2Srch

#### Применение функций ГОСТ47 к получению статистик для данной конкретной задачи
## (по сути адапторы?)
include("compare_qrs.jl")
export MarksQRS, qrs_position_stata, qrs_forms_stata

include("compare_durations.jl")
export duration_pairs_list, duration_err_stata

include("compare_arrhythms.jl")
export MarksArrhythm, arrhythm_byrecord_stata, arrhythm_bycomplex_stata, arrhythm_byseries_stata

include("gross.jl")
export total_gross

### для прогона по базе STDECGDB
const DB_PATH = "//incart.local/fs/guest/skv/STDECGDB"
const STATS_PATH = joinpath(DB_PATH, "stats"); mkpath(STATS_PATH)

###
## Из функций CompareMarkups, по идее, можно собирать кастомные сценарии прогона статистик
# но тут сделаю функцию под прогон по всем статитстикам, т.к. скорее всего это будет самый частый сценарий

include("compare_markups.jl")
export compare_markups

# сравнение таблиц статистики
include("compare_tables.jl")
export compare_stata_tables

#####
function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table! s begin
    "calc"
        help = "Calc stata (comapare markups of two authors)"
        action = :command
    "compare"
        help = "Compare stata tables"
        action = :command
    end

    @add_arg_table! s["calc"] begin
    "--ref_author"
        help = "Ext of an author of the reference markup"
    "--test_author"
        help = "Ext of an author of the test markup"
    "--keyset_file"
        help = "Name of file with keys to search"
    end

    @add_arg_table! s["compare"] begin
    "--old_tables_path"
        help = "Path to old stata tables"
    "--new_tables_path"
        help = "Path to new stata tables"
    end

    args = ArgParse.parse_args_unhandled(Base.ARGS, s) |> ArgParse.convert_to_symbols

    return args
end

function calc_middleware(parsed_args::Dict{Symbol, Any})

    # защита от дурака
    ref_author = last(split(parsed_args[:ref_author], '.'))
    test_author = last(split(parsed_args[:test_author], '.'))
    keysetpath = parsed_args[:keyset_file] |> splitpath |> last |> splitext |> first

    # преобразование в полные пути
    binpath = joinpath(DB_PATH, "bin")
    markpath = joinpath(DB_PATH, "mkp")
    outpath = STATS_PATH
    keys2find = JSON3.read(joinpath(STATS_PATH, keysetpath*".json"), OrderedDict{String, OrderedDict{String, String}})

    return binpath, markpath, outpath, ref_author, test_author, keys2find
end

function compare_middleware(parsed_args::Dict{Symbol, Any})

    # защита от дурака
    old_tables_path = parsed_args[:old_tables_path] |> splitpath |> last |> splitext |> first
    new_tables_path = parsed_args[:new_tables_path] |> splitpath |> last |> splitext |> first

    # преобразование в полные пути
    outpath = STATS_PATH
    old_tables, new_tables = joinpath.(STATS_PATH, (old_tables_path, new_tables_path))

    return old_tables, new_tables, outpath
end

function main()
    parsed_args = parse_commandline()
    @info "Julia started with args: $parsed_args"

    if parsed_args[:_COMMAND_] === :calc
        compare_markups(calc_middleware(parsed_args[:calc])...)
    elseif parsed_args[:_COMMAND_] === :compare
        compare_stata_tables(compare_middleware(parsed_args[:compare])...)
    end
end

# compilation
function julia_main()::Cint
    println("julia_main")
    try
        main()
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end


end
