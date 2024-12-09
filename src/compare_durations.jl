function duration_pairs_list(
    ref_qrs, ref_p, ref_qt,
    test_qrs, test_p, test_qt,
    fs
    )

    # пары индексов для qrs и qt
    qrs_indexpairs = CompareDurations51.complex_pairs(ref_qrs, test_qrs, fs)

    # пары индексов для p
    p_indexpairs = ismissing(ref_p) ? missing : CompareDurations51.complex_pairs(ref_p, test_p, fs)

    # ширины
    ref_p_dur = ismissing(ref_p) ? missing : CompareDurations51.dur_ms.(ref_p, fs)
    test_p_dur = ismissing(test_p) ? missing : CompareDurations51.dur_ms.(test_p, fs)

    ref_qrs_dur = CompareDurations51.dur_ms.(ref_qrs, fs)
    test_qrs_dur = CompareDurations51.dur_ms.(test_qrs, fs)

    ref_qt_dur = ismissing(ref_qt) ? missing : CompareDurations51.dur_ms.(ref_qt, fs)
    test_qt_dur = ismissing(test_qt) ? missing : CompareDurations51.dur_ms.(test_qt, fs)

    # сравниваем qrs и qt по парам индексов для qrs
    qrs_dur_pairs = map(qrs_indexpairs) do (ref_ind, test_ind)
        CompareDurations51.global_duration_pairs(ref_ind, [ref_qrs_dur], test_ind, [test_qrs_dur])
    end

    qt_dur_pairs = any(ismissing, (ref_qt_dur, test_qt_dur)) ? missing : map(qrs_indexpairs) do (ref_ind, test_ind)
        CompareDurations51.global_duration_pairs(ref_ind, [ref_qt_dur], test_ind, [test_qt_dur])
    end

    # сравниваем p по парам индексов для p

    p_dur_pairs = any(ismissing, (ref_p, test_p)) ? missing : map(p_indexpairs) do (ref_ind, test_ind)
        CompareDurations51.global_duration_pairs(ref_ind, [ref_p_dur], test_ind, [test_p_dur])
    end

    return (;qrs_dur_pairs, qt_dur_pairs, p_dur_pairs)
end

duration_pairs_list(ref_mkp::MarkPart, test_mkp::MarkPart) = duration_pairs_list(
    QRS_bounds(ref_mkp, consider_workzone = true),
    P_bounds(ref_mkp, consider_workzone = true),
    QT_bounds(ref_mkp, consider_workzone = true),
    QRS_bounds(test_mkp),
    P_bounds(test_mkp),
    QT_bounds(test_mkp),
    fs(ref_mkp)
)

# статистика по всей базе
function duration_err_gross(qrs_dur_pairs, qt_dur_pairs, p_dur_pairs)

    _, qrs_file_gross = CompareDurations51.report_compare_global(string.(eachindex(qrs_dur_pairs)), ["QRS_dur"], qrs_dur_pairs)
    _, qt_file_gross = ismissing(qt_dur_pairs) ? (missing, missing) : CompareDurations51.report_compare_global(string.(eachindex(qrs_dur_pairs)), ["QT_dur"], qt_dur_pairs)
    _, p_file_gross = ismissing(p_dur_pairs) ? (missing, missing) : CompareDurations51.report_compare_global(string.(eachindex(p_dur_pairs)), ["P_dur"], p_dur_pairs)

    (;
    P_err_mean = ismissing(p_file_gross) ? missing : p_file_gross[1,:mean],
    P_err_std = ismissing(p_file_gross) ? missing : p_file_gross[1,:std],
    QRS_err_mean = qrs_file_gross[1,:mean],
    QRS_err_std = qrs_file_gross[1,:std],
    QT_err_mean = ismissing(qt_file_gross) ? missing : p_file_gross[1,:mean],
    QT_err_std = ismissing(qt_file_gross) ? missing : p_file_gross[1,:std],
    )
end

function duration_err_gross_total(filenames::Vector{String}, eachfile_gross::Vector{<:NamedTuple})

    df = DataFrame(eachfile_gross)
    total_gross = map(x -> filter(!ismissing, x) |> mean |> x -> round(x, digits = 2), eachcol(df))

    insertcols!(df, 1, :filename => filenames)
    push!(df, ["GROSS (mean)", total_gross...])

    return df
end
