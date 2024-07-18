module AbstractMCMC

using BangBang: BangBang
using ConsoleProgressMonitor: ConsoleProgressMonitor
using LogDensityProblems: LogDensityProblems
using LoggingExtras: LoggingExtras
using ProgressLogging: ProgressLogging
using StatsBase: StatsBase
using TerminalLoggers: TerminalLoggers
using Transducers: Transducers
using FillArrays: FillArrays

using Distributed: Distributed
using Logging: Logging
using Random: Random

# Reexport sample
using StatsBase: sample
export sample

# Parallel sampling types
export MCMCThreads, MCMCDistributed, MCMCSerial

"""
    AbstractChains

`AbstractChains` is an abstract type for an object that stores
parameter samples generated through a MCMC process.
"""
abstract type AbstractChains end

"""
    AbstractSampler

The `AbstractSampler` type is intended to be inherited from when
implementing a custom sampler. Any persistent state information should be
saved in a subtype of `AbstractSampler`.

When defining a new sampler, you should also overload the function
`transition_type`, which tells the `sample` function what type of parameter
it should expect to receive.
"""
abstract type AbstractSampler end

"""
    AbstractModel

An `AbstractModel` represents a generic model type that can be used to perform inference.
"""
abstract type AbstractModel end

"""
    AbstractMCMCEnsemble

An `AbstractMCMCEnsemble` algorithm represents a specific algorithm for sampling MCMC chains
in parallel.
"""
abstract type AbstractMCMCEnsemble end

"""
    MCMCThreads

The `MCMCThreads` algorithm allows users to sample MCMC chains in parallel using multiple
threads.
"""
struct MCMCThreads <: AbstractMCMCEnsemble end

"""
    MCMCDistributed

The `MCMCDistributed` algorithm allows users to sample MCMC chains in parallel using multiple
processes.
"""
struct MCMCDistributed <: AbstractMCMCEnsemble end

"""
    MCMCSerial

The `MCMCSerial` algorithm allows users to sample serially, with no thread or process parallelism.
"""
struct MCMCSerial <: AbstractMCMCEnsemble end

"""
    decondition(conditioned_model)

Remove the conditioning (i.e., observation data) from `conditioned_model`, turning it into a
generative model over prior and observed variables.

The invariant 

```
m == condition(decondition(m), obs)
```

should hold for models `m` with conditioned variables `obs`.
"""
function decondition end

"""
    condition(model, observations)

Condition the generative model `model` on some observed data, creating a new model of the (possibly
unnormalized) posterior distribution over them.

`observations` can be of any supported internal trace type, or a fixed probability expression.

The invariant 

```
m = decondition(condition(m, obs))
```

should hold for generative models `m` and arbitrary `obs`.
"""
function condition end

"""
    recompute_logprob!!(rng, model, sampler, state)

Recompute the log-probability of the `model` based on the given `state` and return the resulting state.
"""
function recompute_logprob!!(rng, model, sampler, state) end

"""
    getparams(state)

Returns the values of the parameters in the state.
"""
function getparams(state) end

include("samplingstats.jl")
include("logging.jl")
include("interface.jl")
include("sample.jl")
include("stepper.jl")
include("transducer.jl")
include("logdensityproblems.jl")

end # module AbstractMCMC
