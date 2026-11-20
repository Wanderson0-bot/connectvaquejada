"use client";

import type { FormEvent, ReactNode } from "react";

type ConfirmFormProps = {
  action: (formData: FormData) => void | Promise<void>;
  message: string;
  className?: string;
  children: ReactNode;
};

export function ConfirmForm({ action, message, className, children }: ConfirmFormProps) {
  function confirm(event: FormEvent<HTMLFormElement>) {
    if (!window.confirm(message)) event.preventDefault();
  }

  return (
    <form action={action} onSubmit={confirm} className={className}>
      {children}
    </form>
  );
}
