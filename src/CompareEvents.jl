module CompareEvents

import TimeSamplings as ts
using DataFrames, CSV
using Statistics

export report_comparison
export pair_event_labels, series_pair_event_labels

"""
подсчет статистики по булевым парам
также стоит глянуть:
https://github.com/VaclavMacha/EvalMetrics.jl
https://alan-turing-institute.github.io/MLJ.jl/stable/performance_measures/
"""
struct ConfusionMatrixBinary
    true_positive::Int
    true_negative::Int
    false_positive::Int
    false_negative::Int
end
function Base.:+(m1::ConfusionMatrixBinary, m2::ConfusionMatrixBinary)
    ConfusionMatrixBinary(
        m1.true_positive + m2.true_positive,
        m1.true_negative + m2.true_negative,
        m1.false_positive + m2.false_positive,
        m1.false_negative + m2.false_negative
    )
end
positive(m::ConfusionMatrixBinary) = m.true_positive + m.false_negative
negative(m::ConfusionMatrixBinary) = m.true_negative + m.false_positive
accuracy(m::ConfusionMatrixBinary) = (m.true_positive + m.true_negative)/(positive(m)+negative(m)) # точность
sensivity(m::ConfusionMatrixBinary) = m.true_positive/(m.true_positive + m.false_negative) # чувствительность
precision(m::ConfusionMatrixBinary) = m.true_positive/(m.true_positive + m.false_positive) # предсказательная сила
specificity(m::ConfusionMatrixBinary) = m.true_negative/(m.true_negative + m.false_positive) # специфичность

function ConfusionMatrixBinary(pairs::AbstractVector{<:Tuple{Bool, Bool}})
    true_positive = true_negative = false_positive = false_negative = 0
    for (is_ref, is_test) in pairs
        if is_ref && is_test
            true_positive += 1
        end
        if !is_ref && !is_test
            true_negative += 1
        end
        if !is_ref && is_test
            false_positive += 1
        end
        if is_ref && !is_test
            false_negative += 1
        end
    end

    ConfusionMatrixBinary(true_positive, true_negative, false_positive, false_negative)
end

function ConfusionMatrixBinary(refs::AbstractVector{<:Bool}, tests::AbstractVector{<:Bool})
    true_positive = true_negative = false_positive = false_negative = 0
    for (is_ref, is_test) in zip(refs, tests)
        if is_ref && is_test
            true_positive += 1
        end
        if !is_ref && !is_test
            true_negative += 1
        end
        if !is_ref && is_test
            false_positive += 1
        end
        if is_ref && !is_test
            false_negative += 1
        end
    end

    ConfusionMatrixBinary(true_positive, true_negative, false_positive, false_negative)
end

"""
определение пар позиций и булевых меток событий
"""
function pair_event_labels((ref_Q, ref_is_p), (test_Q, test_is_p), fs)
    # определим область сравнения
    pair_radius = round(Int, fs * 0.150)
    compare_range = max(1, ref_Q[1] - pair_radius) : ref_Q[end] + pair_radius

    # берем из тестовой разметки только события внутри области сравнения (без начальных и конечных Z)
    # samp_ref = ts.Sampler(ref_Q)
    samp_test = ts.Sampler(test_Q)
    test_range = samp_test(compare_range)

    # обрезаем тестовую разметку по участку референтной
    test_Q = @view test_Q[test_range]
    test_is_p = @view test_is_p[test_range]

    i_pairs = ts.outerjoin_pairs_radius(ref_Q, test_Q, pair_radius)

    # подсчитаем булевые пары
    pairs_prem = map(i_pairs) do (i, j)
        p1 = i < 0 ? false : ref_is_p[i]
        p2 = j < 0 ? false : test_is_p[j]
        p1, p2
    end

    # позиции для каждой пары
    pairs_pos = map(i_pairs) do (i, j)
        pos1 = i < 0 ? NaN : ref_Q[i]
        pos2 = j < 0 ? NaN : test_Q[j]
        pos1, pos2
    end

    return pairs_pos, pairs_prem
end

# кортеж с отчетом по матрице замешивания
function row_report_confusion(m::ConfusionMatrixBinary)
    (;
        TP = m.true_positive ,
        TN = m.true_negative ,
        FP = m.false_positive ,
        FN = m.false_negative ,
        Acc = round(accuracy(m) * 100, digits = 1),
        Se = round(sensivity(m) * 100, digits = 1),
        Sp = round(specificity(m) * 100, digits = 1),
        Ppv = round(precision(m) * 100, digits = 1)
    )
end

nanmean(x) = mean(filter(!isnan,x))

# отчет по списку файлов - dataframe
# готовим отчет - итоговую таблицу
function report_comparison(filenames_list, pairs_list)

    confmat_list = ConfusionMatrixBinary.(pairs_list)

    confmat_sum = sum(confmat_list)

    df = DataFrame(row_report_confusion.([confmat_list..., confmat_sum]))
    insertcols!(df, 1, :File => [filenames_list..., "GROSS"])
    n = length(filenames_list)
    m_counts = map(i->df[end,i] ÷ n, 2:5)
    m_stats = nanmean.(eachcol(df[!,6:end]))
    # push!(df, ["AVG" m_counts... m_stats...])
    # пока не будем добавлять строчку средних
    return df
end

function report_comparison(filenames_list, pairs_list, outfile)
    df = report_comparison(filenames_list, pairs_list)
    CSV.write(outfile, df)
end

# статистика по длинным сериям (пароксизмам), отличается от ГОСТ-47 тем,
# что считается не по событиям, а по точкам, т.е. учитывает разницу в длительности серий
# поскольку ориентирована на очень длинные серии, которых нет в госте.
# каждой точке должна быть соотнесена длина текущей серии, либо 0 при ее отсутствии
# для алгоритма будем считать, что ref_Q == test_Q (иначе придется выкусывать лишние события = морока)
function series_pair_event_labels((ref_Q, ref_len), (test_Q, test_len), fs, len_min = 5, len_max = Inf)
    # определим область сравнения
    pair_radius = round(Int, fs * 0.150)
    compare_range = max(1, ref_Q[1] - pair_radius) : ref_Q[end] + pair_radius

    # берем из тестовой разметки только события внутри области сравнения (без начальных и конечных Z)
    # samp_ref = ts.Sampler(ref_Q)
    samp_test = ts.Sampler(test_Q)
    test_range = samp_test(compare_range)

    # обрезаем тестовую разметку по участку референтной
    test_Q = @view test_Q[test_range]

    i_pairs = ts.outerjoin_pairs_radius(ref_Q, test_Q, pair_radius)

    # подсчитаем булевые пары
    pairs_prem = map(i_pairs) do (i, j)
        # отключим добавление в TP длинных детекций на одиночных реф.
        rlen = i > 0 ? ref_len[i] : 0
        tlen = j > 0 ? test_len[j] : 0
        if ((len_min <= rlen <= len_max) && (tlen > 0)) || ((rlen > 0) & (len_min <= tlen <= len_max)) # TP: любой короткий тестовый на длинном референтном или короткий референтный на длинном тестовом
            true, true
        elseif (len_min <= rlen <= len_max) && (tlen == 0) # FN: отсутствия тестовых на длинных референтных
            true, false
        elseif (rlen == 0) && (len_min <= tlen <= len_max) # FP: отсутствия референтных на длинных тестовых
            false, true
        else
            false, false
        end
    end

    # позиции для каждой пары
    pairs_pos = map(i_pairs) do (i, j)
        pos1 = i < 0 ? NaN : ref_Q[i]
        pos2 = j < 0 ? NaN : test_Q[j]
        pos1, pos2
    end

    return pairs_pos, pairs_prem
end

# объединение сравнения и получения статистики
# function get_series_report(ref_Q, ref_len, test_Q, test_len)

#     res = map(zip(qs_list3, p_len_list, fs_list)) do (qs, p_len_test, fs)
#         len_min = 1
#         len_max = 5
#         pairs_pos, pairs_prem = my.series_pair_event_labels((qs.Q, qs.p_len), (qs.Q, p_len_test), fs, len_min, len_max)
#         (; pairs_pos, pairs_prem)
#     end

#     pairs_prem_list = [r.pairs_prem for r in res]

#     df = my.report_comparison(datfilelist, pairs_prem_list)

# end



end
