reserved = join("\\".*[keys(OPERATORS)..., "(", ")"], '|')
const REG = Regex("(?:(?:(?<=($reserved))(?:))|(?:(?:)(?=($reserved))))")

"""
`srch_expr` - условие поиска в `dst`.
пример `srch_expr`: "{base_rhythm} && sinus && (brady || tachy) && !arrhythm"
пример `dst``: "{base_rhythm}-sinus-mono_brady"
"""
function isin(srch_expr::String, dst::String)

    # делим набор ключей, В котором ищем
    dst_parts = split(dst, '-') # чтобы потом искать строго совпадение ключа целиком, а не sinus в sinus_arr, например

    # делим выражение для поиска на составные части С СОХРАНЕНИЕМ операторов (сплиттеров)
    elements = filter(!isempty, split(srch_expr, REG, keepempty = false) .|> strip)

    # идём по каждому компоненту выражения поиска:
    #    - если это логический оператор/скобка, оставляем его на своём месте
    #    - если это ключ, ставим в соответствие булево значение, отражающее, есть ли данный ключ в искомом наборе
    for i in eachindex(elements)
        word = elements[i]
        if !is_operator(word) && !is_bracket(word)
            elements[i] = string((word in dst_parts))
        end
    end

    # # собираем выражение типа "true&&true&&(false||false)&&!false"
    # expr = join(elements)

    # # # разрешаем выражение с помощью встроенных методов
    # return eval(Meta.parse(expr)) # TODO: eval непозволительно долго работает... надо сделать свой калькулятор логических выражений

    return eval_logical_expression(elements) # используем свой калькулятор логических выражений
end

isin_mask(x::String, set::Dict{String, BitVector}, masklen::Int64) = begin
    keys_exist = filter(s -> isin(x, s), keys(set))
    maskset = [set[x] for x in keys_exist]
    if iszero(length(maskset))
        return fill(false, masklen)
    else
        return .!iszero.(sum(maskset))
    end
end

function fixname(name::String)
    name = replace(name,
        "&&" => "and",
        "||" => "or",
        "!" => "not"
    )

    return join(split(name, ' ', keepempty = false))
end
