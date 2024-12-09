module CompareBeat2beat
"""
перенесено из AlgCompare beat2beat
"""

import TimeSamplings as ts
import Descriptors: Gost47QRS
using DataFrames, CSV
# using Statistics


export pair_event_labels, report_comparison_AA2

"""
получение отчета AA2 по списку файлов - суммарной таблицы статистики
"""
function report_comparison_AA2(filenames_list, pairs_form_list)
    M_list = calc_crossmatrix.(pairs_form_list) # кроссматрица по формам
    rows = row_AA2.(M_list) # считаем точность

    M_gross = sum(M_list)
    row_gross = row_AA2(M_gross) # считаем точность

    df = DataFrame([rows..., row_gross])
    insertcols!(df, 1, :File => [filenames_list..., "GROSS"])

    return df
end

"""
сравнение разметок по 47му госту
формы - строки или символы из списка: N, S, V, F, Q, O, X
"""
function pair_event_labels(
    pos_ref::AbstractVector,
    form_ref::AbstractVector,
    pos_test::AbstractVector,
    form_test::AbstractVector,
    freq::Float64;
    radius_ms = 150
    #time_cutstart_sec::Float64 = 0.0,
    # compare::Dict{Symbol, Any} = Dict{Symbol, Any}(), # настройки сравнения
)
    t_radius = round(Int, radius_ms * freq / 1000)
    # t_cutstart = time_cutstart_sec * freq

    # !! работаем БЕЗ КОРРЕКТИРОВКИ форм для Z
    indexpairs = ts.outerjoin_pairs_radius(pos_ref, pos_test, t_radius) #, t_cutstart) #! тут ref первым аргументом

    # @info indexpairs

    pairs_form = Vector{NTuple{2,Symbol}}(undef, length(indexpairs))
    pairs_pos = Vector{NTuple{2,Int}}(undef, length(indexpairs))
    for (k, (i1, i2)) in enumerate(indexpairs)
        t1, f1 = i1 < 1 ? (-1, :O) : (pos_ref[i1], Symbol(form_ref[i1]))
        t2, f2 = i2 < 1 ? (-1, :O) : (pos_test[i2], Symbol(form_test[i2]))
        pairs_pos[k] = (t1, t2)
        pairs_form[k] = (f1, f2)
    end

    correct_pairs!(pairs_form) # adapter? исключаем участки U, VF (это надо делать перед сравнением???)

    return pairs_pos, pairs_form
end

#исключение из пар - фибрилляций VF и шумовых участков U (по ГОСТ-47)
function correct_pairs!(pairs)

    isVF1 = false
    isVF2 = false
    isU1 = false
    isU2 = false
    Np = length(pairs)

    for i = 1:Np

        pair = pairs[i]

        # для участков U меняем соседние O на X: N O U O N -> N X X X N
        isU1 = pair[1] == :U
        isU2 = pair[2] == :U

        if isU1 # U в реферетной разметке
            k1 = i-1
            while k1 >= 1 && pairs[k1][1] == :O
                k1 = k1 - 1
            end
            k2 = i+1
            while k2 <= Np && pairs[k2][1] == :O
                k2 = k2 + 1
            end
            for z = k1+1:k2-1
                pairs[z] = (:X, pairs[z][2])
            end
        end
        if isU2 # U в тестовой разметке
            k1 = i-1
            while k1 >= 1 && pairs[k1][2] == :O
                k1 = k1 - 1
            end
            k2 = i+1
            while k2 <= Np && pairs[k2][2] == :O
                k2 = k2 + 1
            end
            for z = k1+1:k2-1
                pairs[z] = (pairs[z][1], :X)
            end
        end

        # для участков VF

        pair = pairs[i] # ранее могло поменяться

        if pair[1] == Symbol('[') isVF1 = true; end
        if pair[2] == Symbol('[') isVF2 = true; end

        if isVF2 pairs[i] = (pairs[i][1], :O); end # указываем пропуск на тестовом VF
        if isVF1 pairs[i] = (:O,:O); end # исключаем из сравнения на референтном VF

        if pair[1] == Symbol(']') isVF1 = false; end
        if pair[2] == Symbol(']') isVF2 = false; end
    end
    return pairs
end

# расчет матрицы попаданий по массиву пар
# :N, :S, :V, :F, :Q, :O, :X
function calc_crossmatrix(pairs_form)

    M = zeros(Int,7,7) # матрица попаданий

    N = length(pairs_form)

    for i = 1:N

        pair = pairs_form[i];
        k1 = Gost47QRS.sym2code[pair[1]] |> Int # код совпадает с индексом матрицы
        k2 = Gost47QRS.sym2code[pair[2]] |> Int # код совпадает с индексом матрицы

        if k1 <= 7 && k2 <= 7 # прибавляем только валидные метки
            M[k1, k2] += 1
        end

    end
    return M
end

# строка для таблицы AA2
function row_AA2(M)

    # оцениваем точность по матрице ошибок
    qrs, veb, sveb = calc_accuracy(M)

    # и делаем строчку для таблицы
    M_ = short_matrix(M)

    Nn_, Sn_, Vn_, Fn_, On_,
    Ns_, Ss_, Vs_, Fs_, Os_,
    Nv , Sv_, Vv , Fv_, Ov_,
    No_, So_, Vo_, Fo_, _ = M_[:]

    return (;
        Nn_, Sn_, Vn_, Fn_, On_,
        Ns_, Ss_, Vs_, Fs_, Os_,
        Nv , Sv_, Vv , Fv_, Ov_,
        No_, So_, Vo_, Fo_,
        Q_Se = qrs.Se, Q_Pp = qrs.Pp,
        V_Se = veb.Se, V_Pp = veb.Pp, V_FPR = veb.FPR,
        SV_Se = sveb.Se, SV_Pp = sveb.Pp, SV_FPR = sveb.FPR)
end

# сжатая обобщенная матрица AA.3 + недостающие строки с S + SVEB статистика
function short_matrix(M::AbstractArray)
    c1 = [1,4,5] # N+f+q
    c3 = [6,7]   # O+x

    #             N+f+q,            S, V,           O+x,
    M_ = hcat(sum(M[:,c1]; dims=2), M[:,[2,3]], sum(M[:,c3]; dims=2))

    r3 = [4,5] # F+Q
    r4 = [6,7] # O+X

    #              N, V, S,           F+Q                    O+X
    M_short = vcat(M_[[1,2,3],:], sum(M_[r3,:]; dims=1), sum(M_[r4,:]; dims=1))

end
# Результаты qrs, veb, sveb - структуры по каждому типу проверки
function calc_accuracy(M::Array{Int})
    # M - матрица ошибок 7 x 7
    x = M[1:5, 1:5]
    TP = sum(x)

    x = M[6:7, 1:5]
    FP = sum(x)

    x = M[1:5, 6:7]
    FN = sum(x)

    Se = round((TP / ( TP+ FN)) * 100; sigdigits=4)
    Pp = round((TP / ( TP+ FP)) * 100; sigdigits=4)

    qrs = (;TP,FP,FN,Se,Pp)

    # VEB

    x = M[3, 3]
    TP = sum(x)

    x = M[[1,2, 6,7],3]
    FP = sum(x)

    x = M[3,[1,2, 4,5,6,7]]
    FN = sum(x)

    x = M[[1,2, 4,5,6,7], [1,2, 4, 5]]
    TN = sum(x)

    Se  = round((TP / (TP + FN)) * 100; sigdigits=4)
    Pp  = round((TP / (TP + FP)) * 100; sigdigits=4)
    FPR = round((FP / (TN + FP)) * 100; sigdigits=4)

    veb = (; TP, FP, FN, Se, Pp, FPR)

    # SVEB

    x = M[2, 2]
    TP = sum(x)

    x = M[[1, 3,4, 6,7], 2]
    FP = sum(x)

    x = M[2, [1, 3,4,5,6,7]]
    FN = sum(x)

    x = M[[1, 3,4,5,6,7], [1, 3,4,5]]
    TN = sum(x)

    Se =  round((TP / (TP + FN)) * 100; sigdigits=4)
    Pp =  round((TP / (TP + FP)) * 100; sigdigits=4)
    FPR = round((FP / (TN + FP)) * 100; sigdigits=4)

    sveb = (; TP, FP, FN, Se, Pp, FPR)

    return qrs, veb, sveb
end

# ==================== ниже - коды отдельных пар ошибок в разных вариациях ===============

# соответствие форм в сжатых таблицах
const form2shortref = Dict(
    :N => :N,
    :S => :S,
    :V => :V,
    :F => :F,
    :Q => :F,
    :X => :O,
    :O => :O,
)
const form2shorttest = Dict(
    :N => :N,
    :S => :S,
    :V => :V,
    :F => :N,
    :Q => :N,
    :X => :O,
    :O => :O,
)
# преобразовние пары коротких названий (сжатая таблица) - в названия колонок итоговой таблицы
const shortpair2error_AA2 = Dict(
    (:N,:N) => :Nn_, #Добавила ais !!!
    (:S,:N) => :Sn_,
    (:V,:N) => :Vn_,
    (:F,:N) => :Fn_,
    (:O,:N) => :On_,
    (:N,:S) => :Ns_,
    (:S,:S) => :Ss_,
    (:V,:S) => :Vs_,
    (:F,:S) => :Fs_,
    (:O,:S) => :Os_,
    (:N,:V) => :Nv ,
    (:S,:V) => :Sv_,
    (:V,:V) => :Vv ,
    (:F,:V) => :Fv_,
    (:O,:V) => :Ov_,
    (:N,:O) => :No_,
    (:S,:O) => :So_,
    (:V,:O) => :Vo_,
    (:F,:O) => :Fo_,
    (:O,:O) => :Oo_
)

#! все остальные (pair2error_qrs, pair2error_V, pair2error_SV) можно тоже сопоставить через один словарь
function pair2error_AA2(pairs_form::NTuple{2, Symbol})
    ref = form2shortref[pairs_form[1]]
    test = form2shorttest[pairs_form[2]]
    err_name = shortpair2error_AA2[(ref, test)]
end

function pair2error_qrs(pair::NTuple{2, Symbol})

    k1 = Gost47QRS.sym2code[pair[1]] # код совпадает с индексом матрицы
    k2 = Gost47QRS.sym2code[pair[2]] # код совпадает с индексом матрицы

    NSVFQ = (Gost47QRS.N, Gost47QRS.S, Gost47QRS.V, Gost47QRS.F, Gost47QRS.Q)
    OX = (Gost47QRS.O, Gost47QRS.X)

    if k1 in NSVFQ && k2 in NSVFQ
        return :TP # QTP = Nn+Ns+Nv+Nf+Nq+Sn+Ss+Sv+Sf+Sq+Vn+Vs+Vv+Vf+Vq+Fn+Fs+Fv+Ff+Fq+Qn+Qs+Qv+Qf+Qq
    elseif k1 in OX && k2 in NSVFQ
        return :FP # QFP = On+Os+Ov+Of+Oq+Xn+Xs+Xv+Xf+Xq
    elseif k1 in NSVFQ && k2 in OX
        return :FN # QFN = No+Nx+So+Sx+Vo+Vx+Fo+Fx+Qo+Qx
    else
        return :other # что-то невалидное...
    end
end

function pair2error_V(pair::NTuple{2, Symbol})

    k1 = Gost47QRS.sym2code[pair[1]] # код совпадает с индексом матрицы
    k2 = Gost47QRS.sym2code[pair[2]] # код совпадает с индексом матрицы

    NSOX   = (Gost47QRS.N, Gost47QRS.S, Gost47QRS.O, Gost47QRS.X)
    NSFQOX = (Gost47QRS.N, Gost47QRS.S, Gost47QRS.F, Gost47QRS.Q, Gost47QRS.O, Gost47QRS.X)
    NSFQ   = (Gost47QRS.N, Gost47QRS.S, Gost47QRS.F, Gost47QRS.Q)

    if  k1 == Gost47QRS.V && k2 == Gost47QRS.V
        return TP # VTP = Vv
    elseif k1 in NSOX && k2 == Gost47QRS.V
        return :FP # VFP = Nv+Sv+Ov+Xv
    elseif k1 == Gost47QRS.V && k2 in NSFQOX
        return :FN # VFN = Vn+Vs+Vf+Vq+Vo+Vx
    elseif k1 in NSFQOX && k2 in NSFQ
        return :TN # VTN = Nn+Nf+Nq+Ns+Sn+Sf+Sq+Ss+Fn+Ff+Fq+Fs+Qn+Qf+Qq+Qs+On+Of+Oq+Os+Xn+Xf+Xq+Xs
    else
        return :other
    end
end

function pair2error_SV(pair::NTuple{2, Symbol})

    k1 = Gost47QRS.sym2code[pair[1]] # код совпадает с индексом матрицы
    k2 = Gost47QRS.sym2code[pair[2]] # код совпадает с индексом матрицы

    NVFOX  = (Gost47QRS.N, Gost47QRS.V, Gost47QRS.F, Gost47QRS.O, Gost47QRS.X)
    NVFQOX = (Gost47QRS.N, Gost47QRS.V, Gost47QRS.F, Gost47QRS.Q, Gost47QRS.O, Gost47QRS.X)
    NVFQ   = (Gost47QRS.N, Gost47QRS.V, Gost47QRS.F, Gost47QRS.Q)

    if k1 == Gost47QRS.S && k2 == Gost47QRS.S
        return :TP # SVTP = Ss
    elseif k1 in NVFOX && k2 == Gost47QRS.S
        return :FP # SVFP = Ns+Vs+Fs+Os+Xs
    elseif k1 == Gost47QRS.S && k2 in NVFQOX
        return :FN # SVFN = Sn+Sv+Sf+Sq+So+Sx
    elseif k1 in NVFQOX && k2 in NVFQ
        return :TN # SVTN = Nn+Nv+Nf+Nq+Vn+Vv+Vf+Vq+Fn+Fv+Ff+Fq+Qn+Qv+Qf+Qg+On+Ov+Of+Oq+Xn+Xv+Xf+Xq
    else
        return :other
    end
end

#= тест:
pairs_pos, pairs_form = CompareBeat2beat.pair_event_labels(
    [100, 200, 300], [:N, :S, :V],
    [50, 150, 210, 295], [:N, :N, :N, :N],
    250.
)

file_list = ["file1", "file2"]
pairs_list = [pairs_form, pairs_form]

CompareBeat2beat.report_comparison_AA2(file_list, pairs_list)
=#

end
