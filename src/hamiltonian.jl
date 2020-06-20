export to_matrix, SimpleRydberg, subspace,
    RydbergHamiltonian, AbstractRydbergHamiltonian,
    update_hamiltonian!

const ParameterType{T} = Union{T, Vector{T}} where {T <: Number}

getscalarmaybe(x::Vector, k) = x[k]
getscalarmaybe(x::Number, k) = x

function update_hamiltonian!(dst::AbstractMatrix, n::Int, subspace_v, ps...)
    return to_matrix!(dst, n, subspace_v, ps...)
end

function update_hamiltonian!(dst::Hermitian, n::Int, subspace_v, ps...)
    update_hamiltonian!(parent(dst), n, subspace_v, ps...)
    return dst
end

# specialize for SparseMatrixCSC
function update_hamiltonian!(dst::SparseMatrixCSC, n::Int, subspace_v, Ω, ϕ)
    @inbounds for col in 1:size(dst, 1)
        for k in dst.colptr[col]:dst.colptr[col+1]-1
            row = dst.rowval[k]
            lhs = subspace_v[row]
            rhs = subspace_v[col]
            update_x_term!(dst.nzval, lhs, rhs, k, Ω, ϕ)
        end
    end
    return dst
end

function update_hamiltonian!(dst::SparseMatrixCSC, n::Int, subspace_v, Ω, ϕ, Δ)
    @inbounds for col in 1:size(dst, 1)
        for k in dst.colptr[col]:dst.colptr[col+1]-1
            row = dst.rowval[k]
            lhs = subspace_v[row]
            rhs = subspace_v[col]

            if row == col
                update_z_term!(dst.nzval, lhs, n, k, Δ)
            else
                update_x_term!(dst.nzval, lhs, rhs, k, Ω, ϕ)
            end
        end
    end
    return dst
end

Base.@propagate_inbounds function update_x_term!(nzval, lhs, rhs, k, Ω::Real, ϕ::Real)
    mask = lhs ⊻ rhs
    if lhs & mask == 0
        nzval[k] = Ω * exp(im * ϕ)
    else
        nzval[k] = Ω * exp(-im * ϕ)
    end
    return nzval
end

Base.@propagate_inbounds function update_x_term!(nzval, lhs, rhs, k, Ω::AbstractVector{<:Real}, ϕ::AbstractVector{<:Real})
    mask = lhs ⊻ rhs
    # dispatch to nonsigned version to make CUDA happy
    l = log2i(UInt(mask)) + 1
    if lhs & mask == 0
        nzval[k] = Ω[l] * exp(im * ϕ[l])
    else
        nzval[k] = Ω[l] * exp(-im * ϕ[l])
    end
    return nzval
end

Base.@propagate_inbounds function update_z_term!(nzval::AbstractVector{Td}, lhs, n, l, Δ::Real) where Td
    sigma_z = zero(Td)
    for k in 1:n
        if readbit(lhs, k) == 1
            sigma_z -= Δ
        else
            sigma_z += Δ
        end
    end
    nzval[l] = sigma_z
    return dst
end

Base.@propagate_inbounds function update_z_term!(nzval::AbstractVector{Td}, lhs, n, l, Δ::AbstractVector{<:Real}) where Td
    sigma_z = zero(Td)
    for k in 1:n
        if readbit(lhs, k) == 1
            sigma_z -= Δ[k]
        else
            sigma_z += Δ[k]
        end
    end
    nzval[l] = sigma_z
    return dst
end


"""
    sigma_x_term!(dst::AbstractMatrix{T}, n::Int, lhs, i, subspace_v, Ω, ϕ) where {T}

Sigma X term of the Rydberg Hamiltonian in MIS subspace:

```math
\\sum_{i=1}^n Ω_i (e^{iϕ_i})|0⟩⟨1| + e^{-iϕ_i}|1⟩⟨0|)
```
"""
Base.@propagate_inbounds function sigma_x_term!(dst::AbstractMatrix{T}, n::Int, lhs, i, subspace_v, Ω::ParameterType, ϕ::ParameterType) where {T}
    for k in 1:n
        each_k = readbit(lhs, k)
        rhs = flip(lhs, 1 << (k - 1))

        j = searchsortedfirst(subspace_v, rhs)
        if (j != length(subspace_v) + 1) && (rhs == subspace_v[j])
            if each_k == 0
                dst[i, j] = getscalarmaybe(Ω, k) * exp(im * getscalarmaybe(ϕ, k))
            else
                dst[i, j] = getscalarmaybe(Ω, k) * exp(-im * getscalarmaybe(ϕ, k))
            end
        end
    end
    return dst
end

"""
    sigma_z_term!(dst::AbstractMatrix{T}, n::Int, lhs, i, Δ) where {T <: Number}

Sigma Z term of the Rydberg Hamiltonian in MIS subspace.

```math
\\sum_{i=1}^n Δ_i σ_i^z
```
"""
Base.@propagate_inbounds function sigma_z_term!(dst::AbstractMatrix{T}, n::Int, lhs, i, Δ::ParameterType) where {T <: Number}
    sigma_z = zero(T)
    for k in 1:n
        if readbit(lhs, k) == 1
            sigma_z -= getscalarmaybe(Δ, k)
        else
            sigma_z += getscalarmaybe(Δ, k)
        end
    end
    dst[i, i] = sigma_z
    return dst
end

"""
    to_matrix!(dst::AbstractMatrix{T}, n::Int, subspace_v, Ω, ϕ[, Δ]) where T

Create a Rydberg Hamiltonian matrix from given parameters inplacely with blockade approximation.
The matrix is preallocated as `dst`.
"""
function to_matrix!(dst::AbstractMatrix, n::Int, subspace_v, Ω::ParameterType, ϕ::ParameterType, Δ::ParameterType)
    @inbounds for (i, lhs) in enumerate(subspace_v)
        sigma_z_term!(dst, n, lhs, i, Δ)
        sigma_x_term!(dst, n, lhs, i, subspace_v, Ω, ϕ)
    end
    return dst
end

function to_matrix!(dst::AbstractMatrix, n::Int, subspace_v, Ω::ParameterType, ϕ::ParameterType)
    @inbounds for (i, lhs) in enumerate(subspace_v)
        sigma_x_term!(dst, n, lhs, i, subspace_v, Ω, ϕ)
    end
    return dst
end

function init_matrix_and_subspace(graph)
    subspace_v = subspace(graph)
    m = length(subspace_v)
    H = spzeros(ComplexF64, m, m)
    return H, subspace_v
end

function to_matrix(graph, Ω::ParameterType, ϕ::ParameterType, Δ::ParameterType)
    n = nv(graph)
    H, subspace_v = init_matrix_and_subspace(graph)
    to_matrix!(H, n, subspace_v, Ω, ϕ, Δ)
    return Hermitian(H)
end

function to_matrix(graph, Ω::ParameterType, ϕ::ParameterType)
    n = nv(graph)
    H, subspace_v = init_matrix_and_subspace(graph)
    to_matrix!(H, n, subspace_v, Ω, ϕ)
    return Hermitian(H)
end

abstract type AbstractRydbergHamiltonian end

"""
    phase(rydberg_hamiltonian)

Return the phase ϕ on X term of a given Rydberg Hamiltonian.
"""
function phase end

"""
    magnetic_field(Val(:X), rydberg_hamiltonian)

Return the magnetic field Ω of a given Rydberg Hamiltonian for Pauli X.

    magnetic_field(Val(:Z), rydberg_hamiltonian)

Return the magnetic field Δ of a given Rydberg Hamiltonian for Pauli Z.
"""
function magnetic_field end



"""
    SimpleRydberg{T <: Number} <: AbstractRydbergHamiltonian

Simple Rydberg Hamiltonian, there is only one global parameter ϕ, and Δ=0, Ω=1.
"""
struct SimpleRydberg{T <: Number} <: AbstractRydbergHamiltonian
    ϕ::T
end

phase(h::SimpleRydberg) = h.ϕ
magnetic_field(::Val{:X}, h::SimpleRydberg{T}) where T = one(T)
magnetic_field(::Val{:Z}, h::SimpleRydberg{T}) where T = zero(T)

# general case
struct RydbergHamiltonian{T <: Real, OmegaT <: ParameterType{T}, PhiT <: ParameterType{T}, DeltaT <: ParameterType{T}}
    C::T
    Ω::OmegaT
    ϕ::PhiT
    Δ::DeltaT
end

phase(h::RydbergHamiltonian) = h.ϕ
magnetic_field(::Val{:X}, h::RydbergHamiltonian{T}) where T = h.Ω
magnetic_field(::Val{:Z}, h::RydbergHamiltonian{T}) where T = h.Δ

function to_matrix(h::AbstractRydbergHamiltonian, atoms::AbstractVector{<:RydAtom}, radius::Float64)
    g = unit_disk_graph(atoms,radius)
    return to_matrix(g, h.Ω, h.ϕ, h.Δ)
end

function timestep!(st::Vector, h::AbstractRydbergHamiltonian, atoms, t::Float64)
    H = to_matrix(h, atoms)
    return expv(-im * t, H, st)
end
