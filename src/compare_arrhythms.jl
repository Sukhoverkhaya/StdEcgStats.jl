const ConfMark = Dict{Tuple{Bool, Bool}, Symbol}(
    (true, true) => :TP,
    (true, false) => :FP,
    (false, true) => :FN,
    (false, false) => :TN
)

"""
Получение меток для всех параметров оценки аритмий
"""
function arrhythms_pairs_list(keyset, (ref_pos, ref_keyset), (test_pos, test_keyset), fs)

    # метки по ключам событий
    # 1. просто есть/нет
    ref_marks = any(isin.(keyset, collect(keys(ref_keyset))))
    test_marks = any(isin.(keyset, collect(keys(test_keyset))))
    record_pairs = (ref_marks, test_marks)

    ## по событиям и по длительности
    ref_marks = isin_mask(keyset, ref_keyset, length(ref_pos))
    test_marks = isin_mask(keyset, test_keyset, length(test_pos))

    se_pairs, sp_pairs, duration_pairs = CompareSegments.segments_pairs(ref_pos, ref_marks, test_pos, test_marks, round(Int, 0.15*fs))

    return (;record_pairs, se_pairs, sp_pairs, duration_pairs)
end

arrhythms_pairs_list(ref_mkp::MarkPart, test_mkp::MarkPart) = keyset2find::String -> arrhythms_pairs_list(
    keyset2find,
    (R_peaks(ref_mkp; consider_workzone = true), events(ref_mkp; consider_workzone = true)),
    (R_peaks(test_mkp), events(test_mkp)),
    fs(ref_mkp)
)

# Статистика по всей базе
function byrecord_comparison(filenames::Vector{String}, groupname::AbstractString, pairs_list::Vector{Tuple{Bool, Bool}})

    # метки TP, TN, FP, FN по каждой записи
    marks = map(_pair -> ConfMark[_pair], pairs_list)

    # стата по всем меткам
    M = CompareEvents.ConfusionMatrixBinary(pairs_list) # матрица путаницы
    report = CompareEvents.row_report_confusion(M) # TP, TN, FP, FN, Se, Sp, PPv, Acc

    # объединение в датафрейм
    df = DataFrame(
        "File" => [filenames..., propertynames(report)...],
        groupname => [marks..., values(report)...]
        )

    return df
end

function byrecord_report_comparison(
    filenames::Vector{String},
    groupnames::Vector{String},
    pairs_list::Vector{Vector{Tuple{Bool, Bool}}};
    shortname = x -> last(split(x, ('|', ' '), keepempty = false))
    )

    tables = map(zip(groupnames, pairs_list)) do (group, pairs)
        byrecord_comparison(filenames, shortname(group), pairs)
    end

    df = outerjoin(tables..., on = "File")

    gross = df[end-7:end, :] |> permutedims
    rename!(gross, collect(gross[1,:]))
    delete!(gross, 1)
    insertcols!(gross, 1, :Name => groupnames)

    return df, gross
end

segments_report_comparison(
    filenames::Vector{String},
    se_pairs::Vector{Vector{Tuple{UnitRange{Int}, Bool}}},
    sp_pairs::Vector{Vector{Tuple{UnitRange{Int}, Bool}}},
    duration_pairs::Vector{Vector{Tuple{UnitRange{Int}, Bool, Bool}}}
) = CompareSegments.report_comparison(filenames, se_pairs, sp_pairs, duration_pairs)

function join_segmnets_gross(groupnames::Vector{String}, tables::Vector{DataFrame})
    gross = DataFrame([df[end,:] for df in tables])
    rename!(gross, "File" => "Name")
    gross.Name .= groupnames
    return gross
end
