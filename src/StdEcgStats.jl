module StdEcgStats

using JSON3, StructArrays
using ProgressMeter
using DataFrames
using FileUtils
using Statistics
using OrderedCollections
using Dates
using CSV
import TimeSamplings: seg_outerjoin_indexpairs

using RelocatableFolders

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
const SETTINGS_PATH = @path joinpath(pwd(), "settings")

###
## Из функций CompareMarkups, по идее, можно собирать кастомные сценарии прогона статистик
# но тут сделаю функцию под прогон по всем статитстикам, т.к. скорее всего это будет самый частый сценарий

# main
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
    datetime = now()
    date, time = Date(datetime), Time(datetime)
    targetpath = joinpath(outpath, "$(test_author)_VS_$(ref_author)_$(date)T$(hour(time))-$(minute(time))-$(second(time))")
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

# compilation
function julia_main()::Cint
    println("julia_main")
    try
        binpath = joinpath(DB_PATH, "bin")
        markpath = joinpath(DB_PATH, "mkp")
        outpath = joinpath(DB_PATH, "stats"); mkpath(outpath)
        settings = JSON3.read(joinpath(SETTINGS_PATH, "settings.json"), Dict{String, Any})
        ref_author, test_author = settings["ref_author"], settings["test_author"]
        keys2find = JSON3.read(joinpath(SETTINGS_PATH, settings["keys_to_search"]), OrderedDict{String, OrderedDict{String, String}})

        compare_markups(binpath, markpath, outpath, ref_author, test_author, keys2find)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end


end
