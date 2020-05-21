#=
Learner.jl:

Author: Peter Wolf (opus111@gmail.com)

A first cut at a port of the FastAI V2 Learner API to Julia

Basic class for handling the training loop

The original source is here

https://github.com/fastai/fastai2/blob/master/fastai2/learner.py

The documentation is copied from here

https://github.com/fastai/fastai2/blob/master/docs/learner.html

The main purpose of this code is to see if the team likes the method
of defining an interface and implementations in Julia
=#

"""
Basic class handling tweaks of the training loop by changing a [Learner](@ref) in various events

The training loop is defined in [Learner](@ref) a bit below and consists in a minimal set of instructions: looping through the data we:

compute the output of the model from the input
calculate a loss between this output and the desired target
compute the gradients of this loss with respect to all the model parameters
update the parameters accordingly
zero all the gradients

Any tweak of this training loop is defined in a Callback to avoid over-complicating the code of the training loop, and to make it easy to mix and match different techniques (since they'll be defined in different callbacks).

A callback can implement the following methods:

begin_fit
after_fit
begin_train
after_train
begin_epoch
after_epoch
begin_batch
after_batch
begin_validate
after_validate
after_pred
after_loss
after_backward
after_step
after_cancel_batch
after_batch

By default handling of these events do nothing.  Special behavior is implemented by overriding these methods

"""
abstract type AbstractCallback end

"""
Group together a model, some dls and a loss_func to handle training

opt_func will be used to create an optimizer when Learner.fit is called, with lr as a default learning rate. splitter is a function that takes learner.model and returns a list of parameter groups (or just one parameter group if there are no different parameter groups). The default is trainable_params, which returns all trainable parameters of the model.

cbs is one or a list of Callbacks [AbstractCallback](@ref) to pass to the Learner. Callbacks are used for every tweak of the training loop. Each Callback is registered as an attribute of Learner (with camel case). At creation, all the callbacks in defaults.callbacks (TrainEvalCallback, Recorder and ProgressCallback) are associated to the Learner.

metrics is an optional list of metrics, that can be either functions or Metrics (see below).

path and model_dir are used to save and/or load models. Often path will be inferred from dls, but you can override it or pass a Path object to model_dir. Make sure you can write in path/model_dir!

wd is the default weight decay used when training the model; moms, the default momentums used in Learner.fit_one_cycle. wd_bn_bias controls if weight decay is applied to BatchNorm layers and bias.

Lastly, train_bn controls if BatchNorm layers are trained even when they are supposed to be frozen according to the splitter. Our empirical experiments have shown that it's the best behavior for those layers in transfer learning.
"""
mutable struct Learner
    cbs:: Array{AbstractCallback}
    opt
    wd
    n_epoch
    loss
    dls
end

"""
add_cb(learner::Learner,cb::AbstractCallback cb)

Add a new Callback [AbstractCallback](@ref) to this Learner [Learner](@ref)
"""
add_cb(learner::Learner,cb::AbstractCallback) = push!(learner.cbs,cb)

# pass event to all callbacks
_cbs_begin_fit(learner::Learner) =  for c in learner.cbs cb.begin_fit(c,learner) end
_cbs_after_fit(learner::Learner) =  for c in learner.cbs cb.after_fit(c,learner) end
_cbs_begin_train(learner::Learner) =  for c in learner.cbs cb.begin_train(c,learner) end
_cbs_after_train(learner::Learner) =  for c in learner.cbs cb.after_train(c,learner) end
_cbs_begin_epoch(learner::Learner) =  for c in learner.cbs cb.begin_epoch(c,learner) end
_cbs_after_epoch(learner::Learner) =  for c in learner.cbs cb.after_epoch(c,learner) end
_cbs_begin_batch(learner::Learner) =  for c in learner.cbs cb.begin_batch(c,learner) end
_cbs_after_batch(learner::Learner) =  for c in learner.cbs cb.after_batch(c,learner) end
_cbs_begin_validate(learner::Learner) =  for c in learner.cbs cb.begin_validate(c,learner) end
_cbs_after_validate(learner::Learner) =  for c in learner.cbs cb.after_validate(c,learner) end
_cbs_after_pred(learner::Learner) =  for c in learner.cbs cb.after_pred(c,learner) end
_cbs_after_loss(learner::Learner) =  for c in learner.cbs cb.after_loss(c,learner) end
_cbs_after_backward(learner::Learner) =  for c in learner.cbs cb.after_backward(c,learner) end
_cbs_after_step(learner::Learner) =  for c in learner.cbs cb.after_step(c,learner) end
_cbs_after_cancel_batch(learner::Learner) =  for c in learner.cbs cb.after_cancel_batch(c,learner) end
_cbs_after_batch(learner::Learner) =  for c in learner.cbs cb.after_batch(c,learner) end

function _do_begin_fit(learner::Learner, n_epoch)
    learner.n_epoch = n_epoch
    learner.loss = 0.0
    _cbs_begin_fit(learner)
end

function _do_epoch_train(learner::Learner)
    try
        learner.dl = learner.dls.train
        _cbs_begin_train(learner)
        all_batches(learner)
    catch CancelTrainException
        _cbs_after_cancel_train(learner)
    finally
        _cbs_after_train(learner)
    end
end

function _do_epoch_validate(learner::Learner, ds_idx=1, dl=nothing)
    dl = isnothing(dl) ? learner.dls[ds_idx] : dl
    try
        learner.dl = dl
        _cbs_begin_validate(learner)
        # with torch.no_grad(): TODO
        all_batches(learner)
    catch CancelValidException
        _cbs_after_cancel_validate(learner)
    finally
        _cbs_after_validate(learner)
    end
end

function _end_cleanup(learner::Learner)
    learner.dl,learner.xb,learner.yb,learner.pred,learner.loss = nothing,(nothing,),(nothing,),nothing,nothing
end

"""
    fit(learner::Learner, n_epoch, lr=nothing, wd=nothing, cbs=nothing, reset_opt=false)

Fit learner.model for n#94epoch using cbs. Optionally reset#94opt

Uses lr and wd if they are provided, otherwise use the defaults values given by the lr and wd attributes of Learner.

All the examples use synth#94learner which is a simple Learner training a linear regression model.

```
#Training a few epochs should make the model better
learn = synth_learner(lr=1e-2)
#learn.model = learn.model.cpu() TODO
xb,yb = one_batch(learn.dls)
init_loss = loss_func(learn, learn.model(xb), yb)
fit(learn, 6)
@assert learn.loss < init_loss
```
"""
function fit(learner::Learner, n_epoch, lr=nothing, wd=nothing, cbs=nothing, reset_opt=false)
    if reset_opt || isnothing(learner.opt)
        create_opt(learner)
    end
    wd = isnothing(wd) ? learner.wd : wd
    if !isnothing(wd)
        set_hypers(learner.opt,wd=wd)
    end
    set_hypers(learner.opt, lr= isnothing(lr) ? learner.lr : lr)

    try
        _do_begin_fit(learner,n_epoch)
        for epoch in range(n_epoch)
            try
                learner.epoch=epoch
                _cbs_begin_epoch(learner)
                _do_epoch_train(learner)
                _do_epoch_validate(learner)
            catch CancelEpochException
                _cbs_after_cancel_epoch(learner)
            finally
                _cbs_after_epoch(learner)
            end
        end
    catch CancelFitException
        _cbs_after_cancel_fit(learner)
    finally
        _cbs_after_fit(learner)
        _end_cleanup(learner)
    end
end