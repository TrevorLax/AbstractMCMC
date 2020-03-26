# Default implementations of `sample` and `psample`.

function StatsBase.sample(
    model::AbstractModel,
    sampler::AbstractSampler,
    arg;
    kwargs...
)
    return StatsBase.sample(Random.GLOBAL_RNG, model, sampler, arg; kwargs...)
end

function StatsBase.sample(
    rng::Random.AbstractRNG,
    model::AbstractModel,
    sampler::AbstractSampler,
    arg;
    kwargs...
)
    return mcmcsample(rng, model, sampler, arg; kwargs...)
end

function psample(
    model::AbstractModel,
    sampler::AbstractSampler,
    N::Integer,
    nchains::Integer;
    kwargs...
)
    return psample(Random.GLOBAL_RNG, model, sampler, N, nchains; kwargs...)
end

function psample(
    rng::Random.AbstractRNG,
    model::AbstractModel,
    sampler::AbstractSampler,
    N::Integer,
    nchains::Integer;
    kwargs...
)
    return mcmcpsample(rng, model, sampler, N, nchains; kwargs...)
end

# Default implementations of regular and parallel sampling.

"""
    mcmcsample([rng, ]model, sampler, N; kwargs...)

Return `N` samples from the MCMC `sampler` for the provided `model`.

A callback function `f` with type signature
```julia
f(rng, model, sampler, N, iteration, transition; kwargs...)
```
may be provided as keyword argument `callback`. It is called after every sampling step.
"""
function mcmcsample(
    rng::Random.AbstractRNG,
    model::AbstractModel,
    sampler::AbstractSampler,
    N::Integer;
    progress = true,
    progressname = "Sampling",
    callback = (args...; kwargs...) -> nothing,
    chain_type::Type=Any,
    kwargs...
)
    # Check the number of requested samples.
    N > 0 || error("the number of samples must be ≥ 1")

    # Perform any necessary setup.
    sample_init!(rng, model, sampler, N; kwargs...)

    @ifwithprogresslogger progress name=progressname begin
        # Obtain the initial transition.
        transition = step!(rng, model, sampler, N; iteration=1, kwargs...)

        # Run callback.
        callback(rng, model, sampler, N, 1, transition; kwargs...)

        # Save the transition.
        transitions = transitions_init(transition, model, sampler, N; kwargs...)
        transitions_save!(transitions, 1, transition, model, sampler, N; kwargs...)

        # Update the progress bar.
        progress && ProgressLogging.@logprogress 1/N

        # Step through the sampler.
        for i in 2:N
            # Obtain the next transition.
            transition = step!(rng, model, sampler, N, transition; iteration=i, kwargs...)

            # Run callback.
            callback(rng, model, sampler, N, i, transition; kwargs...)

            # Save the transition.
            transitions_save!(transitions, i, transition, model, sampler, N; kwargs...)

            # Update the progress bar.
            progress && ProgressLogging.@logprogress i/N
        end
    end

    # Wrap up the sampler, if necessary.
    sample_end!(rng, model, sampler, N, transitions; kwargs...)

    return bundle_samples(rng, model, sampler, N, transitions, chain_type; kwargs...)
end

"""
    mcmcsample([rng, ]model, sampler, isdone; kwargs...)

Continuously draw samples until a convergence criterion `isdone` returns `true`.

The function `isdone` has the signature
```julia
isdone(rng, model, sampler, transitions, iteration; kwargs...)
```
and should return `true` when sampling should end, and `false` otherwise.

A callback function `f` with type signature
```julia
f(rng, model, sampler, N, iteration, transition; kwargs...)
```
may be provided as keyword argument `callback`. It is called after every sampling step.
"""
function mcmcsample(
    rng::Random.AbstractRNG,
    model::AbstractModel,
    sampler::AbstractSampler,
    isdone;
    chain_type::Type=Any,
    progress = true,
    progressname = "Convergence sampling",
    callback = (args...; kwargs...) -> nothing,
    kwargs...
)
    # Perform any necessary setup.
    sample_init!(rng, model, sampler, 1; kwargs...)

    @ifwithprogresslogger progress name=progressname begin
        # Obtain the initial transition.
        transition = step!(rng, model, sampler, 1; iteration=1, kwargs...)

        # Run callback.
        callback(rng, model, sampler, 1, 1, transition; kwargs...)

        # Save the transition.
        transitions = transitions_init(transition, model, sampler; kwargs...)

        # Step through the sampler until stopping.
        i = 2

        while !isdone(rng, model, sampler, transitions, i; progress=progress, kwargs...)
            # Obtain the next transition.
            transition = step!(rng, model, sampler, 1, transition; iteration=i, kwargs...)

            # Run callback.
            callback(rng, model, sampler, 1, i, transition; kwargs...)

            # Save the transition.
            transitions_save!(transitions, i, transition, model, sampler; kwargs...)

            # Increment iteration counter.
            i += 1
        end
    end

    # Wrap up the sampler, if necessary.
    sample_end!(rng, model, sampler, i, transitions; kwargs...)

    # Wrap the samples up.
    return bundle_samples(rng, model, sampler, i, transitions, chain_type; kwargs...)
end

"""
    mcmcpsample([rng, ]model, sampler, N, nchains; kwargs...)

Sample `nchains` chains using the available threads, and combine them into a single chain.

By default, the random number generator, the model and the samplers are deep copied for each
thread to prevent contamination between threads.
"""
function mcmcpsample(
    rng::Random.AbstractRNG,
    model::AbstractModel,
    sampler::AbstractSampler,
    N::Integer,
    nchains::Integer;
    progress = true,
    progressname = "Parallel sampling",
    kwargs...
)
    # Copy the random number generator, model, and sample for each thread
    rngs = [deepcopy(rng) for _ in 1:Threads.nthreads()]
    models = [deepcopy(model) for _ in 1:Threads.nthreads()]
    samplers = [deepcopy(sampler) for _ in 1:Threads.nthreads()]

    # Create a seed for each chain using the provided random number generator.
    seeds = rand(rng, UInt, nchains)

    # Set up a chains vector.
    chains = Vector{Any}(undef, nchains)

    @ifwithprogresslogger progress name=progressname begin
        # Create a channel for progress logging.
        if progress
            channel = Distributed.RemoteChannel(() -> Channel{Bool}(nchains), 1)
        end

        Distributed.@sync begin
            if progress
                Distributed.@async begin
                    # Update the progress bar.
                    progresschains = 0
                    while take!(channel)
                        progresschains += 1
                        ProgressLogging.@logprogress progresschains/nchains
                    end
                end
            end

            Distributed.@async begin
                Threads.@threads for i in 1:nchains
                    # Obtain the ID of the current thread.
                    id = Threads.threadid()

                    # Seed the thread-specific random number generator with the pre-made seed.
                    subrng = rngs[id]
                    Random.seed!(subrng, seeds[i])

                    # Sample a chain and save it to the vector.
                    chains[i] = StatsBase.sample(subrng, models[id], samplers[id], N;
                                                 progress = false, kwargs...)

                    # Update the progress bar.
                    progress && put!(channel, true)
                end

                # Stop updating the progress bar.
                progress && put!(channel, false)
            end
        end
    end

    # Concatenate the chains together.
    return reduce(chainscat, chains)
end