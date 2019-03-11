/*
 * Copyright 2019, Data61
 * Commonwealth Scientific and Industrial Research Organisation (CSIRO)
 * ABN 41 687 119 230.
 *
 * This software may be distributed and modified according to the terms of
 * the BSD 2-Clause license. Note that NO WARRANTY is provided.
 * See "LICENSE_BSD2.txt" for details.
 *
 * @TAG(DATA61_BSD)
 */

#include <assert.h>
#include <camkes/irq.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <utils/util.h>

#define CHECK_MEMBER_EQUAL(a, b, member) a->member == b->member

static bool check_irq_info_is_equal(ps_irq_t *a, ps_irq_t *b)
{
    if (a->type == b->type) {
        switch (a->type) {
        case PS_MSI:
            if (CHECK_MEMBER_EQUAL(a, b, ioapic.ioapic) &&
                CHECK_MEMBER_EQUAL(a, b, ioapic.pin) &&
                CHECK_MEMBER_EQUAL(a, b, ioapic.level) &&
                CHECK_MEMBER_EQUAL(a, b, ioapic.polarity) &&
                CHECK_MEMBER_EQUAL(a, b, ioapic.vector)) {
                return true;
            }
            return false;
        case PS_IOAPIC:
            if (CHECK_MEMBER_EQUAL(a, b, msi.pci_bus) &&
                CHECK_MEMBER_EQUAL(a, b, msi.pci_dev) &&
                CHECK_MEMBER_EQUAL(a, b, msi.pci_func) &&
                CHECK_MEMBER_EQUAL(a, b, msi.handle) &&
                CHECK_MEMBER_EQUAL(a, b, msi.vector)) {
                return true;
            }
            return false;
        case PS_INTERRUPT:
            if (CHECK_MEMBER_EQUAL(a, b, irq.number)) {
                return true;
            }
            return false;
        case PS_TRIGGER:
            if (CHECK_MEMBER_EQUAL(a, b, trigger.number) &&
                CHECK_MEMBER_EQUAL(a, b, trigger.trigger)) {
                return true;
            }
        /* No need for return false here, it'll fall through */
        default:
            return false;
        }
    }

    return false;
}

static allocated_irq_t **find_matching_irq_entry_by_interrupt(ps_irq_t *irq)
{
    for (allocated_irq_t **irq_entry = __start__allocated_irqs;
         irq_entry < __stop__allocated_irqs; irq_entry++) {
        /* We use this function for 'register', so the IRQ entries have to be unallocated */
        if ((*irq_entry)->is_allocated == false) {
            ps_irq_t *irq_info = &((*irq_entry)->irq);
            if (check_irq_info_is_equal(irq_info, irq)) {
                return irq_entry;
            }
        }
    }

    return NULL;
}

static allocated_irq_t **find_matching_irq_entry_by_cptr(seL4_CPtr irq_cptr)
{
    for (allocated_irq_t **irq_entry = __start__allocated_irqs;
         irq_entry < __stop__allocated_irqs; irq_entry++) {
        /* We use this function for 'unregister', so the IRQ entries have to be allocated */
        if ((*irq_entry)->is_allocated == true) {
            if ((*irq_entry)->irq_handler == irq_cptr) {
                return irq_entry;
            }
        }
    }

    return NULL;
}

static irq_id_t camkes_irq_register(void *cookie, ps_irq_t irq, irq_callback_t callback, void *callback_data)
{
    if (!callback) {
        return -EINVAL;
    }

    allocated_irq_t **irq_entry = find_matching_irq_entry_by_interrupt(&irq);

    if (irq_entry == NULL) {
        ZF_LOGE("Couldn't find an unallocated interrupt with the same details");
        return -ENOENT;
    }

    /* Acknowledge the IRQ handler so that signals can arrive on the paired ntfn */
    int error = seL4_IRQHandler_Ack((*irq_entry)->irq_handler);
    if (error) {
        ZF_LOGE("Failed to register interrupt");
        return -EFAULT;
    }

    /* Fill in the book keeping information for this interrupt */
    (*irq_entry)->is_allocated = true;
    (*irq_entry)->callback_fn = callback;
    (*irq_entry)->callback_data = callback_data;

    return (irq_id_t)(*irq_entry)->irq_handler;
}

static int camkes_irq_unregister(void *cookie, irq_id_t irq_id)
{
    if (irq_id < 0) {
        return -EINVAL;
    }

    allocated_irq_t **irq_entry = find_matching_irq_entry_by_cptr((seL4_CPtr) irq_id);

    if (irq_entry == NULL) {
        ZF_LOGE("Couldn't find an allocated interrupt with the same IRQ ID");
        return -ENOENT;
    }

    /* Acknolwedge the IRQ handler so interrupts can arrive */
    int error = seL4_IRQHandler_Ack((*irq_entry)->irq_handler);
    if (error) {
        ZF_LOGE("Failed to register intterupt");
        return -EFAULT;
    }

    (*irq_entry)->is_allocated = false;
    (*irq_entry)->callback_fn = NULL;
    (*irq_entry)->callback_data = NULL;

    return 0;
}

int camkes_irq_ops(ps_irq_ops_t *irq_ops)
{
    if (!irq_ops) {
        return -EINVAL;
    }

    /* The cookie can't be NULL, otherwise the wrappers in libplatsupport will return errors */
    irq_ops->cookie = 0xDEADBEEF;
    irq_ops->irq_register_fn = camkes_irq_register;
    irq_ops->irq_unregister_fn = camkes_irq_unregister;

    return 0;
}