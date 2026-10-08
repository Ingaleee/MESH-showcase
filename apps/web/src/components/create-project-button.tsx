"use client";

import { useState, type ReactNode } from "react";
import { ArrowRight } from "lucide-react";
import { useSession } from "./session-provider";
import { ProjectForm } from "./project-form";

export function CreateProjectButton({
  className = "mesh-button mesh-button-dark",
  ariaLabel,
  children = "Создать проект",
}: {
  className?: string;
  ariaLabel?: string;
  children?: ReactNode;
}) {
  const { account, loading, openLogin } = useSession();
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        className={className}
        aria-label={ariaLabel}
        disabled={loading}
        onClick={() => (account ? setOpen(true) : openLogin())}
      >
        {children}
        <ArrowRight size={18} aria-hidden="true" />
      </button>
      {open && <ProjectForm onClose={() => setOpen(false)} />}
    </>
  );
}
