export function Paisagem({ className = "" }: { className?: string }) {
  return <div aria-hidden="true" className={`relative isolate overflow-hidden bg-gradient-to-b from-sky-200 via-sky-100 to-[#ebf9ff] ${className}`}>
    <div className="absolute left-[43%] top-[13%] h-[20%] w-[24%] rounded-full bg-white" />
    <div className="absolute left-[49%] top-[9%] h-[26%] w-[15%] rounded-full bg-white" />
    <div className="absolute left-[60%] top-[16%] h-[18%] w-[19%] rounded-full bg-white" />
    <div className="absolute -bottom-[11%] left-[-8%] h-[40%] w-[116%] rotate-[-3deg] rounded-[50%] bg-lime-300" />
    <div className="absolute -bottom-[18%] left-[-7%] h-[39%] w-[116%] rotate-[1deg] rounded-[48%] bg-lime-600" />
  </div>;
}
