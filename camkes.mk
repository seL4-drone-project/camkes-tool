#
# Copyright 2014, NICTA
#
# This software may be distributed and modified according to the terms of
# the BSD 2-Clause license. Note that NO WARRANTY is provided.
# See "LICENSE_BSD2.txt" for details.
#
# @TAG(NICTA_BSD)
#

# The variable 'TARGETS' should have been set by our includer.
ifeq (${TARGETS},)
$(error TARGETS not set)
endif

# Only support a single target.
ifneq ($(words ${TARGETS}),1)
$(error Multiple targets specified)
endif

# The variable 'ADL' should have been set by our includer.
ifeq (${ADL},)
$(error ADL not set)
endif

# The main function generated by CAmkES does not conform to the standard main
# signatures, so disable warnings for this.
NK_CFLAGS += -Wno-main

export CONFIG_CAMKES_USE_EXTERNAL_OBJDUMP \
    CONFIG_CAMKES_PYTHON_OPTIMIZE \
    CONFIG_CAMKES_DISABLE_PYTHON_IMPORT_CHECKS \
    CONFIG_CAMKES_PYTHON_INTERPRETER_CPYTHON \
    CONFIG_CAMKES_PYTHON_INTERPRETER_PYPY \
    CONFIG_CAMKES_PYTHON_INTERPRETER_FIGLEAF \
    CONFIG_CAMKES_PYTHON_INTERPRETER_COVERAGE

# Strip the quotes from the string CONFIG_CAMKES_IMPORT_PATH.
CONFIG_CAMKES_IMPORT_PATH:=$(patsubst %",%,$(patsubst "%,%,${CONFIG_CAMKES_IMPORT_PATH}))
#")") Help syntax-highlighting editors.

CAMKES_FLAGS += \
    $(if ${V},--debug,) \
    --cache $(if ${CONFIG_CAMKES_CACHE_READWRITE},on,$(if ${CONFIG_CAMKES_CACHE_READONLY},readonly,$(if ${CONFIG_CAMKES_CACHE_WRITEONLY},writeonly,off))) \
    $(if ${CONFIG_CAMKES_CPP},--cpp,) \
    --cpp-flag=-I${KERNEL_ROOT_PATH}/../include/generated \
    $(if ${CONFIG_CAMKES_DEBUG_POST_RENDER_EDIT},--post-render-edit,) \
    $(foreach path, ${PWD}/tools/camkes/include/builtin ${CONFIG_CAMKES_IMPORT_PATH}, --import-path=${path}) \
    $(if ${TEMPLATES},--templates "${SOURCE_DIR}/${TEMPLATES}",) \
    $(if ${CONFIG_CAMKES_OPTIMISATION_RPC_LOCK_ELISION},--frpc-lock-elision,--fno-rpc-lock-elision) \
    $(if ${CONFIG_CAMKES_OPTIMISATION_CALL_LEAVE_REPLY_CAP},--fcall-leave-reply-cap,--fno-call-leave-reply-cap) \
    $(if ${CONFIG_CAMKES_OPTIMISATION_SPECIALISE_SYSCALL_STUBS},--fspecialise-syscall-stubs,--fno-specialise-syscall-stubs) \
    $(if ${CONFIG_CAMKES_PROVIDE_TCB_CAPS},--fprovide-tcb-caps,--fno-provide-tcb-caps) \
    $(if ${CONFIG_CAMKES_SUPPORT_INIT},--fsupport-init,--fno-support-init) \
    --default-priority ${CONFIG_CAMKES_DEFAULT_PRIORITY} \
    $(if ${CONFIG_CAMKES_PROFILER_INTERNAL},--profiler internal,) \
    $(if ${CONFIG_CAMKES_PROFILER_NATIVE},--profiler native,) \
    $(if ${CONFIG_CAMKES_PROFILER_AGGREGATE},--profiler aggregate,) \
    $(if ${CONFIG_CAMKES_PROFILER_HEARTBEAT},--profiler heartbeat,) \
    $(if ${CONFIG_CAMKES_LARGE_FRAME_PROMOTION},--largeframe,) \
    $(if ${CONFIG_CAMKES_PRUNE_GENERATED},--prune,) \
    $(if ${CONFIG_CAMKES_PLY_OPTIMIZE},--ply-optimise,) \
    $(if ${ARM_HYP},--hyp,) \

include ${SEL4_COMMON}/common.mk

# Generalised rule to override the one provided in common.mk. The reason we
# need to override it is in order to pass extra, per-instance include
# directories. Note that the default target invoked still remains the first one
# encountered in common.mk because this is an implicit rule.
ifeq (${CONFIG_BUILDSYS_CPP_SEPARATE},y)
%.o: %.c_pp
	@$(if $(filter-out 0,${V}),$(warning Using CAmkES generic .o target),)
	@echo " [CC] $(notdir $@)"
	$(Q)mkdir -p $(dir $@)
	$(Q)$(CC) -x c $(CFLAGS) $(CPPFLAGS) $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))) -c $< -o $@
else
%.o: %.c $(HFILES) | install-headers
	@$(if $(filter-out 0,${V}),$(warning Using CAmkES generic .o target),)
	@echo " [CC] $(notdir $@)"
	$(Q)mkdir -p $(dir $@)
	@# Abuse second parameter of make-depend to extend CFLAGS.
	$(Q)$(call make-depend,$<,$@ $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))),$(patsubst %.o,%.d,$@))
	$(Q)$(CC) -x c $(CFLAGS) $(CPPFLAGS) $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))) -c $< -o $@
endif

%.o: %.cxx $(HFILES) | install-headers
	@$(if $(filter-out 0,${V}),$(warning Using CAmkES generic .o target),)
	@echo " [CXX] $(notdir $@)"
	$(Q)mkdir -p $(dir $@)
	@# Abuse second parameter of make-depend to extend CXXFLAGS.
	$(Q)$(call make-cxx-depend,$<,$@ $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))),$(patsubst %.o,%.d,$@))
	$(Q)$(CXX) -x c++ $(CXXFLAGS) $(CPPFLAGS) $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))) -c $< -o $@

.PRECIOUS: %.c_pp
%.c_pp: %.c $(HFILES) | install-headers
	@$(if $(filter-out 0,${V}),$(warning Using CAmkES generic .c_pp target),)
	@echo " [CPP] $(notdir $@)"
	$(Q)mkdir -p $(dir $@)
	@# Abuse second parameter of make-depend to extend CFLAGS.
	$(Q)$(call make-depend,$<,$@ $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))),$(patsubst %.c_pp,%.d,$@))
	$(Q)$(CC) -E \
        $(if ${CONFIG_BUILDSYS_CPP_RETAIN_COMMENTS},-C -CC,) \
        $(if ${CONFIG_BUILDSYS_CPP_LINE_DIRECTIVES},,-P) \
        $(CFLAGS) $(CPPFLAGS) $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))) -c $< -o $@

%.o: %.S $(HFILES) | install-headers
	@$(if $(filter-out 0,${V}),$(warning Using CAmkES generic .o target),)
	@echo " [ASM] $(notdir $@)"
	$(Q)mkdir -p $(dir $@)
	$(Q)$(call make-depend,$<,$@ $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))),$(patsubst %.o,%.d,$@))
	$(Q)$(CC) $(ASFLAGS) $(CPPFLAGS) $(foreach v,$(filter-out $<,$^),$(patsubst %,-I%,$(abspath $(dir ${v})))) -c $< -o $@

# Libraries that are utilised or assumed to exist by the CAmkES runtime or glue
# code. Components are forced to link against these. Note sel4camkes needs to
# come before sel4platsupport to make sure we get the sel4camkes _start, not
# the sel4platsupport one.
CAMKES_CORE_LIBS = sel4 sel4debug c ${CONFIG_CAMKES_SYSLIB} sel4camkes \
    sel4sync utils sel4vka sel4utils sel4platsupport platsupport

PRUNER_BLACKLIST = FILE fpos_t opterr optind optopt stderr stdin stdout \
  va_list __isoc_va_list max_align_t camkes_error_t camkes_error_handler_t \
  pthread_attr_t pthread_mutex_t pthread_cond_t pthread_rwlock_t \
  pthread_barrier_t sel4bench_arm1136_pmnc_t

# The included Makefile is generated automatically by the following rule at the
# bottom of this Makefile.
include ${BUILD_DIR}/camkes-gen.mk

.DELETE_ON_ERROR: ${BUILD_DIR}/camkes-gen.mk
${BUILD_DIR}/camkes-gen.mk: ${SOURCE_DIR}/${ADL}
	@echo " [GEN] $(notdir $@)"
	camkes.sh runner \
        ${CAMKES_FLAGS} \
        --file $< \
        --item Makefile \
        --outfile "$@"
