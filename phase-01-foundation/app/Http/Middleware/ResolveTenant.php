<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Support\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class ResolveTenant
{
    public function __construct(private readonly TenantContext $tenantContext)
    {
    }

    public function handle(Request $request, Closure $next): Response
    {
        $tenantId = $this->resolveTenantId($request);

        if ($tenantId === null) {
            return new JsonResponse([
                'message' => 'Unable to resolve tenant context.',
            ], 404);
        }

        $this->tenantContext->set($tenantId);

        try {
            return $next($request);
        } finally {
            $this->tenantContext->clear();
        }
    }

    private function resolveTenantId(Request $request): ?string
    {
        $host = $request->getHost();
        $parts = explode('.', $host);

        if (count($parts) > 2 && $parts[0] !== 'www') {
            return $parts[0];
        }

        $headerTenant = $request->headers->get('X-Tenant-Id');
        if (is_string($headerTenant) && $headerTenant !== '') {
            return $headerTenant;
        }

        $user = $request->user();
        if ($user !== null && isset($user->tenant_id)) {
            return (string) $user->tenant_id;
        }

        return null;
    }
}
