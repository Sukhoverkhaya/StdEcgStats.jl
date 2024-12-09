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

function formatted_now()
    datetime = now()
    date, time = Date(datetime), Time(datetime)
    return "$(date)T$(hour(time))-$(minute(time))-$(second(time))"
end

"""
Сравнение разметок двух авторов
"""
function compare_markups(
    binpath::AbstractString,
    markpath::AbstractString,
    outpath::AbstractString,
    ref_author::AbstractString,
    test_author::AbstractString,
    keys2find::OrderedDict{String, OrderedDict{String, String}}) # TODO: предусмотреть игнорирование забракованых записей и работу с коллекциями

    # чтение разметок
    common_filenames, markups = read_markups(markpath, binpath, ref_author, test_author);

    # статистики по QRS
    qrs_marks = map(x -> qrs_pairs_list(x...), markups) |> StructVector
    qrs_detector_stats = qrs_position_stata(common_filenames, qrs_marks.pairs_pos)
    qrs_forms_stats =  qrs_forms_stata(common_filenames, qrs_marks.pairs_form)

    # статистика по ширинам
    duration_pairs = map(mkps -> duration_pairs_list(mkps...), markups)
    eachfile_gross = map(pair -> duration_err_gross(pair...), duration_pairs)
    duration_stats = duration_err_gross_total(common_filenames, eachfile_gross)

    totalgroups = collect(keys(keys2find))
    keys_stats = Vector{Tuple{DataFrame, DataFrame, Vector{DataFrame}, DataFrame}}(undef, length(totalgroups))
    @showprogress "Рассчет статистики по аритмиям..."  for (i, totalname) in enumerate(totalgroups)

        # ищем пары по указанному правилам
        groupnames = collect(keys(keys2find[totalname]))
        pairs_list = map(groupnames) do groupname
            rule = keys2find[totalname][groupname]
            map(x -> arrhythms_pairs_list(x...)(rule), markups) |> StructVector
        end

        # таблицы по записям
        byrecord_pairs = [x.record_pairs for x in pairs_list]
        byrecrd_stats, byrecord_gross = byrecord_report_comparison(common_filenames, groupnames, byrecord_pairs)

        # таблицы по сегментам
        segments_stats = map(pairs_list) do marks
            segments_report_comparison(
                common_filenames,
                marks.se_pairs,
                marks.sp_pairs,
                marks.duration_pairs
            )
        end
        segments_gross = join_segmnets_gross(groupnames, segments_stats)

        keys_stats[i] = byrecrd_stats, byrecord_gross, segments_stats, segments_gross
    end

    # сохранение
    targetpath = joinpath(outpath, "$(test_author)_VS_$(ref_author)_$(formatted_now())")
    mkpath(targetpath)

    # TODO: надо бы вынести сохранение в функции рассчета статистик, по примеру CompareEvents....
    # но надо сохранить возможность объединения таблиц

    CSV.write(joinpath(targetpath, "qrs_detector.csv"), qrs_detector_stats)
    CSV.write(joinpath(targetpath, "qrs_forms.csv"), qrs_forms_stats)
    CSV.write(joinpath(targetpath, "durations_err.csv"), duration_stats)

    # для аритмий группируем по типу события и заранее заданному группирующему параметру (имя группы)
    dst = joinpath(targetpath, "Ритмы и аритмии"); mkpath(dst)
    byrecord_target = joinpath(dst, "По записям"); mkpath(byrecord_target)
    segments_target = joinpath(dst, "По сегментам"); mkpath(segments_target)
    for (i, totalname) in enumerate(keys(keys2find))
        record_stats, record_gross, segments_stats, segments_gross = keys_stats[i]

        CSV.write(joinpath(byrecord_target, "$totalname.csv"), record_stats)
        CSV.write(joinpath(byrecord_target, "GROSS_$totalname.csv"), record_gross)

        target = joinpath(segments_target, totalname); mkpath(target)
        for (j, groupname) in enumerate(keys(keys2find[totalname]))
            mainpart, _ = split(groupname, ('|', ' '), keepempty = false)
            CSV.write(joinpath(target, "$mainpart.csv"), segments_stats[j])
        end

        CSV.write(joinpath(segments_target, "GROSS_$totalname.csv"), segments_gross)
    end
end

"""
Сравнение таблиц статистики между двумя прогонами
"""
function compare_stata_tables(old_tables::AbstractString, new_tables::AbstractString, outpath::AbstractString)

    dst = joinpath(outpath, "comparison_$(formatted_now())")
    mkpath(dst)

    write(open(joinpath(dst, "readme.txt"), "w"), join(pairs((;old_tables, new_tables)), '\n'))

    for table in ("qrs_detector", "qrs_forms", "durations_err")
        delta = gross_delta(joinpath.((old_tables, new_tables), table*".csv")..., 1)[:,2:end]

        CSV.write(joinpath(dst, "DELTA_$table.csv"), delta)
    end

    for table_type in ("По записям", "По сегментам")
        mkpath(joinpath(dst, table_type))
        for gross_type in ("GROSS_Ритмы", "GROSS_Эктопические комплексы", "GROSS_Узловое проведение")
            grosspath = joinpath("Ритмы и аритмии", table_type, gross_type*".csv")
            delta = gross_delta(joinpath.((old_tables, new_tables), grosspath)...)

            table_name = split(gross_type, "GROSS")[end]
            CSV.write(joinpath(dst, table_type, "DELTA$table_name.csv"), delta)
        end
    end
end

function gross_delta(old_gross::DataFrame, new_gross::DataFrame, n_last_rows::Int = -1)

    (size(old_gross) != size(new_gross)) && error("Tables to comparison must be the same length")

    nrows, _ = size(new_gross)
    rows_rng = (n_last_rows == -1) ? (1:nrows) : (nrows-n_last_rows+1:nrows)

    oldM = Matrix(old_gross[rows_rng, 2:end])
    newM = Matrix(new_gross[rows_rng, 2:end])
    deltaM = newM - oldM

    delta_df = DataFrame(names(new_gross)[2:end] .=> eachcol(deltaM))
    insertcols!(delta_df, 1, first(names(new_gross)) => new_gross[rows_rng,1])

    return delta_df
end

function gross_delta(old_path::String, new_path::String, n_last_rows::Int = -1)
    old_gross = CSV.read(old_path, DataFrame)
    new_gross = CSV.read(new_path, DataFrame)

    return gross_delta(old_gross, new_gross, n_last_rows)
end

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
