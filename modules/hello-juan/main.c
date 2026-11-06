// hello-juan: first from-scratch pongoOS module.
// Runs below iOS on the iPad mini 2 (A7) after checkm8 entry.
// Registers a read-only `juan` diagnostic command and chains the pre-boot hook.
#include <pongo.h>

#define DIAGNOSTIC_BYTE_LIMIT 64
#define COMMAND_BUFFER_LIMIT 0x1ff

static void (*next_preboot_hook)(void);

static void print_info(void);
static void print_bootargs(void);
static void print_display(void);

static void my_preboot_hook(void) {
    puts("[hello-juan] pre-boot hook reached");
    if (next_preboot_hook) next_preboot_hook();
}

static uint32_t bounded_length(uint32_t length) {
    return length < DIAGNOSTIC_BYTE_LIMIT ? length : DIAGNOSTIC_BYTE_LIMIT;
}

static void print_property_data(const void *value, uint32_t length) {
    const uint8_t *bytes = value;
    uint32_t shown = bounded_length(length);

    for (uint32_t index = 0; index < shown; ++index) {
        iprintf("%02x", bytes[index]);
        if ((index + 1) % 16 == 0 || index + 1 == shown) {
            puts("");
        } else {
            puts(" ");
        }
    }

    if (length > shown) {
        iprintf("... %u of %u bytes shown\n", shown, length);
    }
}

static int print_direct_property(void *context, dt_node_t *node, int depth,
                                 const char *key, void *value, uint32_t length) {
    (void)context;
    (void)node;
    (void)depth;
    iprintf("%s (%u bytes):\n", key, length);
    print_property_data(value, length);
    return 0;
}

static void print_tree_string(const char *label, const char *property) {
    uint32_t length = 0;
    const uint8_t *value = dt_prop(gDeviceTree, property, &length);

    if (!value) {
        iprintf("%s: not available\n", label);
        return;
    }

    if (length && value[length - 1] == 0) {
        --length;
    }

    iprintf("%s: ", label);
    for (uint32_t index = 0; index < length; ++index) {
        uint8_t character = value[index];
        if (character < 0x20 || character >= 0x7f) {
            puts("<binary>");
            return;
        }
        iprintf("%c", character);
    }
    puts("");
}

static void print_help(void) {
    puts("juan commands:");
    puts("  juan [help]              show this help");
    puts("  juan summary             show the complete safe diagnostic summary");
    puts("  juan info                show device, boot, memory, and tree summary");
    puts("  juan bootargs            show the boot-arguments structure");
    puts("  juan display             show framebuffer geometry");
    puts("  juan dt <node> [prop]    show direct node properties or one property");
}

static void print_summary(void) {
    puts("[hello-juan] summary");
    print_info();
    puts("");
    print_bootargs();
    puts("");
    print_display();
    puts("");
    if (gDeviceTree) {
        iprintf("Device-tree root: 0x%llx, %u direct properties, %u children\n",
                (uint64_t)gDeviceTree, gDeviceTree->nprop, gDeviceTree->nchld);
    } else {
        puts("Device-tree root: unavailable");
    }
}

static void print_info(void) {
    if (!gBootArgs) {
        puts("[hello-juan] gBootArgs is unavailable");
        return;
    }
    if (!gDeviceTree) {
        puts("[hello-juan] gDeviceTree is unavailable");
        return;
    }

    puts("Device: iPad mini 2 Wi-Fi (expected iPad4,4 / Apple A7)");
    print_tree_string("Device-tree model", "model");
    print_tree_string("Compatible", "compatible");
    iprintf("Boot arguments: revision 0x%x, version 0x%x\n",
            gBootArgs->Revision, gBootArgs->Version);
    iprintf("Memory: 0x%llx bytes (%llu MiB), physical base 0x%llx\n",
            gBootArgs->memSize, gBootArgs->memSize >> 20, gBootArgs->physBase);
    iprintf("Framebuffer: %ux%u, depth 0x%lx, base 0x%lx\n",
            (unsigned int)gBootArgs->Video.v_width,
            (unsigned int)gBootArgs->Video.v_height,
            (unsigned long)gBootArgs->Video.v_depth,
            (unsigned long)gBootArgs->Video.v_baseAddr);
    iprintf("Device tree: root 0x%llx, %u direct properties, %u direct children\n",
            (uint64_t)gBootArgs->deviceTreeP, gDeviceTree->nprop,
            gDeviceTree->nchld);
}

static void print_bootargs(void) {
    if (!gBootArgs) {
        puts("[hello-juan] gBootArgs is unavailable");
        return;
    }

    iprintf("Revision: 0x%x\n", gBootArgs->Revision);
    iprintf("Version: 0x%x\n", gBootArgs->Version);
    iprintf("Virtual base: 0x%llx\n", gBootArgs->virtBase);
    iprintf("Physical base: 0x%llx\n", gBootArgs->physBase);
    iprintf("Memory size: 0x%llx\n", gBootArgs->memSize);
    iprintf("Top of kernel data: 0x%llx\n", gBootArgs->topOfKernelData);
    iprintf("Machine type: 0x%x\n", gBootArgs->machineType);
    iprintf("Device tree pointer: 0x%llx\n", (uint64_t)gBootArgs->deviceTreeP);
    iprintf("Device tree length: 0x%x\n", gBootArgs->deviceTreeLength);
    iprintf("Command line (iOS 12 layout): %s\n", gBootArgs->iOS12.CommandLine);
    iprintf("Boot flags (iOS 12 layout): 0x%llx\n", gBootArgs->iOS12.bootFlags);
    iprintf("Actual memory (iOS 12 layout): 0x%llx\n",
            gBootArgs->iOS12.memSizeActual);
}

static void print_display(void) {
    if (!gBootArgs) {
        puts("[hello-juan] gBootArgs is unavailable");
        return;
    }

    iprintf("Base address: 0x%lx\n", (unsigned long)gBootArgs->Video.v_baseAddr);
    iprintf("Display code: 0x%lx\n", (unsigned long)gBootArgs->Video.v_display);
    iprintf("Row bytes: %lu\n", (unsigned long)gBootArgs->Video.v_rowBytes);
    iprintf("Width: %lu\n", (unsigned long)gBootArgs->Video.v_width);
    iprintf("Height: %lu\n", (unsigned long)gBootArgs->Video.v_height);
    iprintf("Depth/flags: 0x%lx\n", (unsigned long)gBootArgs->Video.v_depth);
    iprintf("Framebuffer size: 0x%llx bytes\n",
            (uint64_t)gBootArgs->Video.v_rowBytes *
                (uint64_t)gBootArgs->Video.v_height);
}

static void print_device_tree(char *path, char *property) {
    dt_node_t *node = NULL;

    if (!gDeviceTree) {
        puts("[hello-juan] gDeviceTree is unavailable");
        return;
    }
    if (!path || !*path) {
        puts("Usage: juan dt <node> [property]");
        return;
    }

    node = strcmp(path, "/") == 0 ? gDeviceTree : dt_find(gDeviceTree, path);
    if (!node) {
        iprintf("Node not found: %s\n", path);
        return;
    }

    iprintf("Node: %s (%u properties, %u children)\n", path, node->nprop,
            node->nchld);
    if (!property || !*property) {
        dt_parse(node, -1, NULL, NULL, NULL, print_direct_property, NULL);
        return;
    }

    uint32_t length = 0;
    void *value = dt_prop(node, property, &length);
    if (!value) {
        iprintf("Property not found: %s\n", property);
        return;
    }
    iprintf("%s (%u bytes):\n", property, length);
    print_property_data(value, length);
}

static void cmd_juan(const char *cmd, char *args) {
    char *subcommand = args;

    if (!subcommand || !*subcommand || strcmp(subcommand, "help") == 0) {
        print_help();
        return;
    }

    if (strcmp(subcommand, "summary") == 0) {
        print_summary();
    } else if (strcmp(subcommand, "info") == 0) {
        print_info();
    } else if (strcmp(subcommand, "bootargs") == 0) {
        print_bootargs();
    } else if (strcmp(subcommand, "display") == 0) {
        print_display();
    } else if (strcmp(subcommand, "dt") == 0) {
        char *path = args;
        char *property = command_tokenize(
            path, COMMAND_BUFFER_LIMIT - (uint32_t)(path - cmd));
        print_device_tree(path, property);
    } else {
        iprintf("Unknown juan subcommand: %s\n", subcommand);
        print_help();
    }
}

void module_entry(void) {
    next_preboot_hook = preboot_hook;
    preboot_hook = my_preboot_hook;
    command_register("juan", "read-only device diagnostics", cmd_juan);
}

char *module_name = "hello-juan";

struct pongo_exports exported_symbols[] = {
    {.name = 0, .value = 0}
};
