/*
 * zcgltf C smoke test: proves the installed headers and static library are
 * usable from plain C with no Zig anywhere. It also covers what the Zig-side
 * ABI check structurally cannot: pointee TYPES are erased by `[*c]` pointers
 * there, so actually parsing through the real structs is the evidence that
 * the pointed-to data agrees too.
 */
#include <cgltf.h>
#include <cgltf_write.h>

#include <stdio.h>
#include <string.h>

static const char k_gltf[] =
    "{\"asset\":{\"version\":\"2.0\"},"
    "\"scene\":0,"
    "\"scenes\":[{\"nodes\":[0]}],"
    "\"nodes\":[{\"name\":\"root\"}]}";

int main(void) {
    cgltf_options options;
    cgltf_data* data = NULL;
    cgltf_result result;
    cgltf_size json_size;

    memset(&options, 0, sizeof(options));

    result = cgltf_parse(&options, k_gltf, sizeof(k_gltf) - 1, &data);
    if (result != cgltf_result_success) {
        fprintf(stderr, "cgltf_parse: %d\n", (int)result);
        return 1;
    }
    result = cgltf_validate(data);
    if (result != cgltf_result_success) {
        fprintf(stderr, "cgltf_validate: %d\n", (int)result);
        return 1;
    }
    if (data->scenes_count != 1 || data->nodes_count != 1) {
        fprintf(stderr, "unexpected counts: %d scenes, %d nodes\n",
                (int)data->scenes_count, (int)data->nodes_count);
        return 1;
    }
    if (data->scene != &data->scenes[0] ||
        cgltf_node_index(data, &data->nodes[0]) != 0) {
        fprintf(stderr, "scene/node wiring is wrong\n");
        return 1;
    }

    /* The writer, size-query form: proves cgltf_write.h linked too. */
    json_size = cgltf_write(&options, NULL, 0, data);
    if (json_size == 0) {
        fprintf(stderr, "cgltf_write returned 0 for a valid document\n");
        return 1;
    }

    cgltf_free(data);
    printf("zcgltf c smoke test passed\n");
    return 0;
}
