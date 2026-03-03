<?php

declare(strict_types=1);

namespace App\Support\Tenancy;

use RuntimeException;

class TenantContext
{
    private ?string $tenantId = null;

    public function set(string $tenantId): void
    {
        $this->tenantId = $tenantId;
    }

    public function get(): ?string
    {
        return $this->tenantId;
    }

    public function require(): string
    {
        if ($this->tenantId === null) {
            throw new RuntimeException('Tenant context is not set for this request.');
        }

        return $this->tenantId;
    }

    public function clear(): void
    {
        $this->tenantId = null;
    }
}
