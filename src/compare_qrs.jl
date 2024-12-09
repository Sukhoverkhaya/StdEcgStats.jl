"""
Получеие меток для всех параметров оценки QRS
"""
function qrs_pairs_list(ref_pos, ref_forms, test_pos, test_forms, fs)

    # TODO: исключать X и Z из анализа!

    # метки по позициям и формам комплексов
    indexpairs, pairs_form = CompareForms.pair_event_labels(ref_pos, ref_forms, test_pos, test_forms, fs)
    pairs_pos = map(x -> x .> 0, indexpairs)

    return (;pairs_pos, pairs_form)
end

qrs_pairs_list(ref_mkp::MarkPart, test_mkp::MarkPart) = qrs_pairs_list(
    R_peaks(ref_mkp; consider_workzone = true),
    QRS_form(ref_mkp; consider_workzone = true) .|> first .|> string,
    R_peaks(test_mkp),
    QRS_form(test_mkp) .|> first .|> string,
    fs(ref_mkp)
)

# Статистика по всей базе
qrs_position_stata(
    filenames::Vector{String},
    pairs_pos::Vector{Vector{NTuple{2, Bool}}},
) = CompareEvents.report_comparison(filenames, pairs_pos)

qrs_forms_stata(
    filenames::Vector{String},
    pairs_form::Vector{Vector{NTuple{2, Symbol}}},
) = CompareForms.report_comparison(filenames, pairs_form)
