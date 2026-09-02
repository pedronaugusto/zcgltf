/*
 * A downstream C consumer: proves the artifact links and both headers
 * install under their published names, through b.dependency + linkLibrary
 * alone.
 */
#include <stdio.h>
#include <string.h>

#include <cgltf.h>
#include <cgltf_write.h>

static const char k_gltf[] =
    "{\"asset\":{\"version\":\"2.0\"},"
    "\"nodes\":[{\"name\":\"a\",\"translation\":[1.0,2.0,3.0]}]}";

int main(void) {
    cgltf_options options;
    cgltf_data* data = NULL;
    cgltf_float matrix[16];
    cgltf_size json_size;

    memset(&options, 0, sizeof(options));
    if (cgltf_parse(&options, k_gltf, sizeof(k_gltf) - 1, &data) != cgltf_result_success) {
        fprintf(stderr, "c consumer: parse failed\n");
        return 1;
    }
    cgltf_node_transform_local(&data->nodes[0], matrix);
    if (matrix[12] != 1.0f || matrix[13] != 2.0f || matrix[14] != 3.0f) {
        fprintf(stderr, "c consumer: translation not in the transform\n");
        return 1;
    }
    json_size = cgltf_write(&options, NULL, 0, data);
    if (json_size == 0) {
        fprintf(stderr, "c consumer: write size query failed\n");
        return 1;
    }
    printf("c consumer ok: %d node(s), %d write bytes\n",
        (int)data->nodes_count, (int)json_size);
    cgltf_free(data);
    return 0;
}
