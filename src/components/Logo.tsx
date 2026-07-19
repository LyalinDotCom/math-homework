export function Logo({ large = false }: { large?: boolean }) {
  return (
    <span
      className={large ? "brand-mark large" : "brand-mark"}
      aria-hidden="true"
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={3.4}
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M5 12.6l4.4 4.4L19 7.4" />
      </svg>
    </span>
  );
}
