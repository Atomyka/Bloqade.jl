# Copyright 2021 QuEra Computing Inc. All rights reserved.

module EaRydLattices

using NearestNeighbors
using Viznet: Viznet
using Viznet.Compose

export # types
    AbstractLattice, HoneycombLattice,
    SquareLattice, TriangularLattice, ChainLattice,
    LiebLattice, KagomeLattice, GeneralLattice,
    # interfaces
    generate_sites, offset_axes, random_dropout, rescale_axes,
    clip_axes, lattice_sites, lattice_vectors,
    # grid
    MaskedGrid, make_grid, locations,
    # nearest neighbors
    make_kdtree, grouped_nearest, DistanceGroup,
    # visualize
    viz_atoms, viz_maskedgrid

include("lattice.jl")
include("neighbors.jl")
include("visualize.jl")

end