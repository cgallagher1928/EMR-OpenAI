<?php

declare(strict_types=1);

use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'service' => 'emr-api',
    ]);
});

Route::middleware(['auth:sanctum', 'resolve.tenant'])->get('/tenant/context', function (TenantContext $tenantContext) {
    return response()->json([
        'tenant_id' => $tenantContext->require(),
    ]);
});
